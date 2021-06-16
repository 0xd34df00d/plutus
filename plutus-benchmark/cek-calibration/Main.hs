{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeOperators     #-}

-- See Note [Creation of the Cost Model]
module Main (main) where


import qualified Prelude                                  as Haskell

import           PlutusCore
import qualified PlutusTx                                 as Tx
import           PlutusTx.Prelude                         as Tx
import           UntypedPlutusCore                        as UPLC
import           UntypedPlutusCore.Evaluation.Machine.Cek

import           Control.Exception
import           Control.Monad.Except
import           Criterion.Main
import qualified Criterion.Types                          as C


type PlainTerm = UPLC.Term Name DefaultUni DefaultFun ()


{-
-- TODO.  I'm not totally sure what's going on here.  `env` is supposed to
-- produce data that will be supplied to the things being benchmarked.  Here
-- we've got a term and we evaluate it to get back the budget consumed, but then
-- we throw that away and evaluate the term again.  This may have the effect of
-- avoiding warmup, which could be a good thing.  Let's look into that.
runTermBench :: Haskell.String -> PlainTerm -> Benchmark
runTermBench name term = env
    (do
        (_result, budget) <-
          pure $ (unsafeEvaluateCek defaultCekParameters) term
        pure budget
        )
    $ \_ -> bench name $ nf (unsafeEvaluateCek defaultCekParameters) term
-}

benchCek :: UPLC.Term NamedDeBruijn DefaultUni DefaultFun () -> Benchmarkable
benchCek t = case runExcept @UPLC.FreeVariableError $ runQuoteT $ UPLC.unDeBruijnTerm t of
    Left e   -> throw e
    Right t' -> nf (unsafeEvaluateCek defaultCekParameters) t'


{-# INLINABLE rev #-}
rev :: [()] -> [()]
rev l0 = rev' l0 []
    where rev' l acc =
              case l of
                []   -> acc
                x:xs -> rev' xs (x:acc)

{-# INLINABLE mkList #-}
mkList :: Integer -> [()]
mkList m = mkList' m []
    where mkList' n acc =
              if n == 0 then acc
              else mkList' (n-1) (():acc)

{-# INLINABLE zipl #-}
zipl :: [()] -> [()] -> [()]
zipl [] []         = []
zipl l []          = l
zipl [] l          = l
zipl (x:xs) (y:ys) = x:y:(zipl xs ys)

{-# INLINABLE go #-}
go :: Integer -> [()]
go n = zipl (mkList n) (rev $ mkList n)

mkListTerm :: Integer -> UPLC.Term NamedDeBruijn DefaultUni DefaultFun ()
mkListTerm n =
  let (UPLC.Program _ _ code) = Tx.getPlc $ $$(Tx.compile [|| go ||]) `Tx.applyCode` Tx.liftCode n
  in code

mkListBM :: Integer -> Benchmark
mkListBM n = bench (Haskell.show n) $ benchCek (mkListTerm n)

mkListBMs :: [Integer] -> Benchmark
mkListBMs ns = bgroup "List" [mkListBM n | n <- ns]


main :: Haskell.IO ()
main = defaultMainWith (defaultConfig { C.csvFile = Just csvFile }) $ [mkListBMs [0,10..1000]]

