module MainFrame.View where

import Prologue hiding (div)
import Dashboard.View (dashboardCard, dashboardScreen)
import Data.Lens (view, (^.))
import Effect.Aff.Class (class MonadAff)
import Halogen (ComponentHTML)
import Halogen.Css (classNames)
import Halogen.Extra (renderSubmodule)
import Halogen.HTML (div)
import MainFrame.Lenses (_currentSlot, _dashboardState, _subState, _toast, _tzOffset, _welcomeState)
import MainFrame.Types (Action(..), ChildSlots, State)
import Toast.View (renderToast)
import Welcome.View (welcomeCard, welcomeScreen)

render :: forall m. MonadAff m => State -> ComponentHTML Action ChildSlots m
render state =
  let
    currentSlot = state ^. _currentSlot

    tzOffset = state ^. _tzOffset
  in
    div [ classNames [ "h-full" ] ]
      $ case view _subState state of
          Left _ ->
            [ renderSubmodule _welcomeState WelcomeAction welcomeScreen state
            , renderSubmodule _welcomeState WelcomeAction welcomeCard state
            ]
          Right _ ->
            [ renderSubmodule _dashboardState DashboardAction (dashboardScreen { currentSlot, tzOffset }) state
            , renderSubmodule _dashboardState DashboardAction (dashboardCard currentSlot) state
            ]
      <> [ renderSubmodule _toast ToastAction renderToast state ]
