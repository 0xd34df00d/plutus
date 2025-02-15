{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE DerivingStrategies   #-}
{-# LANGUAGE DerivingVia          #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE ImpredicativeTypes   #-}
{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ViewPatterns         #-}
{-# options_ghc -Wno-missing-signatures #-}
{-

A beam-specific effect for writing to a beam database. Here we explicitly construct the
database schema for the data which we wish to store:

- Datums
- Scripts
- Transactions
- Transaction output references indexed by address

In particular this is specialised to 'Sqlite'; but it could be refactored to
work over a more general type, or changed to Postgres.

The schema we've opted for at present is a very simple one, with no ability to
track changes over time.

-}

module Plutus.ChainIndex.DbStore where

import           Cardano.BM.Trace                         (Trace, logDebug)
import           Control.Concurrent                       (threadDelay)
import           Control.Exception                        (try)
import           Control.Monad.Freer                      (Eff, LastMember, Member, type (~>))
import           Control.Monad.Freer.Error                (Error, throwError)
import           Control.Monad.Freer.TH                   (makeEffect)
import           Data.ByteString                          (ByteString)
import           Data.Foldable                            (traverse_)
import           Data.Kind                                (Constraint)
import           Data.Semigroup.Generic                   (GenericSemigroupMonoid (..))
import qualified Data.Text                                as Text
import           Data.Word                                (Word64)
import           Database.Beam                            (Beamable, Columnar, Database, DatabaseEntity,
                                                           DatabaseSettings, FromBackendRow, Generic, Identity,
                                                           MonadIO (liftIO), SqlDelete, SqlSelect, SqlUpdate,
                                                           Table (..), TableEntity, dbModification, insertValues,
                                                           runDelete, runInsert, runSelectReturningList,
                                                           runSelectReturningOne, runUpdate, withDbModification)
import           Database.Beam.Backend.SQL                (BeamSqlBackendCanSerialize)
import           Database.Beam.Backend.SQL.BeamExtensions (BeamHasInsertOnConflict (anyConflict, insertOnConflict, onConflictDoNothing))
import           Database.Beam.Migrate                    (CheckedDatabaseSettings, defaultMigratableDbSettings,
                                                           renameCheckedEntity, unCheckDatabase)
import           Database.Beam.Schema.Tables              (FieldsFulfillConstraint)
import           Database.Beam.Sqlite                     (Sqlite, SqliteM, runBeamSqliteDebug)
import qualified Database.SQLite.Simple                   as Sqlite
import           Plutus.ChainIndex.ChainIndexError        (ChainIndexError (..))
import           Plutus.ChainIndex.ChainIndexLog          (ChainIndexLog (..))

data DatumRowT f = DatumRow
    { _datumRowHash  :: Columnar f ByteString
    , _datumRowDatum :: Columnar f ByteString
    } deriving (Generic, Beamable)

type DatumRow = DatumRowT Identity

instance Table DatumRowT where
    data PrimaryKey DatumRowT f = DatumRowId (Columnar f ByteString) deriving (Generic, Beamable)
    primaryKey = DatumRowId . _datumRowHash

data ScriptRowT f = ScriptRow
    { _scriptRowHash   :: Columnar f ByteString
    , _scriptRowScript :: Columnar f ByteString
    } deriving (Generic, Beamable)

type ScriptRow = ScriptRowT Identity

instance Table ScriptRowT where
    data PrimaryKey ScriptRowT f = ScriptRowId (Columnar f ByteString) deriving (Generic, Beamable)
    primaryKey = ScriptRowId . _scriptRowHash

data TxRowT f = TxRow
    { _txRowTxId :: Columnar f ByteString
    , _txRowTx   :: Columnar f ByteString
    } deriving (Generic, Beamable)

type TxRow = TxRowT Identity

instance Table TxRowT where
    data PrimaryKey TxRowT f = TxRowId (Columnar f ByteString) deriving (Generic, Beamable)
    primaryKey = TxRowId . _txRowTxId

data AddressRowT f = AddressRow
    { _addressRowCred   :: Columnar f ByteString
    , _addressRowOutRef :: Columnar f ByteString
    } deriving (Generic, Beamable)

type AddressRow = AddressRowT Identity

instance Table AddressRowT where
    -- We also need an index on just the _addressRowCred column, but the primary key index provides this
    -- as long as _addressRowCred is the first column in the primary key.
    data PrimaryKey AddressRowT f = AddressRowId (Columnar f ByteString) (Columnar f ByteString) deriving (Generic, Beamable)
    primaryKey (AddressRow c o) = AddressRowId c o

data TipRowT f = TipRow
    { _tipRowSlot        :: Columnar f Word64 -- In Plutus Slot is Integer, but in the Cardano API it is Word64, so this is safe
    , _tipRowBlockId     :: Columnar f ByteString
    , _tipRowBlockNumber :: Columnar f Word64
    } deriving (Generic, Beamable)

type TipRow = TipRowT Identity

instance Table TipRowT where
    data PrimaryKey TipRowT f = TipRowId { unTipRowId :: Columnar f Word64 } deriving (Generic, Beamable)
    primaryKey = TipRowId . _tipRowSlot

{-
The UnspentOutputRow and UnmatchedInputRow tables represent the TxUtxoBalance part of the UtxoState data on disk.
In particular the tip is the one that produced the utxo, except for the rows
that come from transactions that can no longer be rolled back:
In the UtxoState data that can no longer be rolled back are combined in a single TxUtxoBalance value.
The tip in those cases is the most recent tip that can no longer be rolled back.
(This is an automatic result of the Monoid instance on TxUtxoBalance, and is a bit weird when spelled
out as a database design, but the disk state and in memory state should be kept in sync.)
-}

data UnspentOutputRowT f = UnspentOutputRow
    { _unspentOutputRowTip    :: PrimaryKey TipRowT f
    , _unspentOutputRowOutRef :: Columnar f ByteString
    } deriving (Generic, Beamable)

type UnspentOutputRow = UnspentOutputRowT Identity

instance Table UnspentOutputRowT where
    data PrimaryKey UnspentOutputRowT f = UnspentOutputRowId (PrimaryKey TipRowT f) (Columnar f ByteString) deriving (Generic, Beamable)
    primaryKey (UnspentOutputRow t o) = UnspentOutputRowId t o

data UnmatchedInputRowT f = UnmatchedInputRow
    { _unmatchedInputRowTip    :: PrimaryKey TipRowT f
    , _unmatchedInputRowOutRef :: Columnar f ByteString
    } deriving (Generic, Beamable)

type UnmatchedInputRow = UnmatchedInputRowT Identity

instance Table UnmatchedInputRowT where
    data PrimaryKey UnmatchedInputRowT f = UnmatchedInputRowId (PrimaryKey TipRowT f) (Columnar f ByteString) deriving (Generic, Beamable)
    primaryKey (UnmatchedInputRow t o) = UnmatchedInputRowId t o

data Db f = Db
    { datumRows          :: f (TableEntity DatumRowT)
    , scriptRows         :: f (TableEntity ScriptRowT)
    , txRows             :: f (TableEntity TxRowT)
    , addressRows        :: f (TableEntity AddressRowT)
    , tipRows            :: f (TableEntity TipRowT)
    , unspentOutputRows  :: f (TableEntity UnspentOutputRowT)
    , unmatchedInputRows :: f (TableEntity UnmatchedInputRowT)
    } deriving (Generic, Database be)

type AllTables (c :: * -> Constraint) f =
    ( c (f (TableEntity DatumRowT))
    , c (f (TableEntity ScriptRowT))
    , c (f (TableEntity TxRowT))
    , c (f (TableEntity AddressRowT))
    , c (f (TableEntity TipRowT))
    , c (f (TableEntity UnspentOutputRowT))
    , c (f (TableEntity UnmatchedInputRowT))
    )
deriving via (GenericSemigroupMonoid (Db f)) instance AllTables Semigroup f => Semigroup (Db f)
deriving via (GenericSemigroupMonoid (Db f)) instance AllTables Monoid f => Monoid (Db f)

db :: DatabaseSettings Sqlite Db
db = unCheckDatabase checkedSqliteDb

checkedSqliteDb :: CheckedDatabaseSettings Sqlite Db
checkedSqliteDb = defaultMigratableDbSettings
    `withDbModification` dbModification
    { datumRows   = renameCheckedEntity (const "datums")
    , scriptRows  = renameCheckedEntity (const "scripts")
    , txRows      = renameCheckedEntity (const "txs")
    , addressRows = renameCheckedEntity (const "addresses")
    , tipRows     = renameCheckedEntity (const "tips")
    , unspentOutputRows  = renameCheckedEntity (const "unspent_outputs")
    , unmatchedInputRows = renameCheckedEntity (const "unmatched_inputs")
    }

type BeamableSqlite table = (Beamable table, FieldsFulfillConstraint (BeamSqlBackendCanSerialize Sqlite) table)

-- | Effect for managing a beam-based database.
data DbStoreEffect r where
    -- | Insert a row into a table.
    AddRows
        :: BeamableSqlite table
        => DatabaseEntity Sqlite Db (TableEntity table)
        -> [table Identity]
        -> DbStoreEffect ()

    UpdateRows
        :: Beamable table
        => SqlUpdate Sqlite table
        -> DbStoreEffect ()

    DeleteRows
        :: Beamable table
        => SqlDelete Sqlite table
        -> DbStoreEffect ()

    SelectList
        :: FromBackendRow Sqlite a
        => SqlSelect Sqlite a
        -> DbStoreEffect [a]

    SelectOne
        :: FromBackendRow Sqlite a
        => SqlSelect Sqlite a
        -> DbStoreEffect (Maybe a)

    Combined
        :: [DbStoreEffect ()]
        -> DbStoreEffect ()

handleDbStore ::
    forall effs.
    ( Member (Error ChainIndexError) effs
    , LastMember IO effs
    )
    => Trace IO ChainIndexLog
    -> Sqlite.Connection
    -> DbStoreEffect
    ~> Eff effs
handleDbStore trace conn eff = runBeam trace conn $ execute eff
    where
        execute :: DbStoreEffect ~> SqliteM
        execute = \case
            AddRows _ [] -> pure ()
            -- Workaround for "too many SQL variables" sqlite error
            -- The maximum is 999, and this only happens in this case with tables of 2 columns, rounded down to 400 rows just in case
            AddRows table (splitAt 400 -> (batch, rest)) -> do
                runInsert $ insertOnConflict table (insertValues batch) anyConflict onConflictDoNothing
                execute $ AddRows table rest

            UpdateRows q -> runUpdate q
            DeleteRows q -> runDelete q
            SelectList q -> runSelectReturningList q
            SelectOne q -> runSelectReturningOne q
            Combined effs -> traverse_ execute effs


runBeam ::
    forall effs.
    ( Member (Error ChainIndexError) effs
    , LastMember IO effs
    )
    => Trace IO ChainIndexLog
    -> Sqlite.Connection
    -> SqliteM
    ~> Eff effs
runBeam trace conn action = loop (5::Int)
    where
        loop retries = do
            let traceSql = logDebug trace . SqlLog
            resultEither <- liftIO $ try $ runBeamSqliteDebug traceSql conn action
            case resultEither of
                -- 'Database.SQLite.Simple.ErrorError' corresponds to an SQL error or
                -- missing database. When this exception is raised, we suppose it's
                -- because the another transaction was already running.
                Left (Sqlite.SQLError Sqlite.ErrorError _ _) | retries > 0 -> do
                    liftIO $ threadDelay 100000
                    loop (retries - 1)
                -- We handle and rethrow errors other than
                -- 'Database.SQLite.Simple.ErrorError'.
                Left e -> do
                    throwError $ SqlError $ Text.pack $ show e
                Right v -> return v

makeEffect ''DbStoreEffect
