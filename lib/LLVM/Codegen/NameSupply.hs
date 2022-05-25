module LLVM.Codegen.NameSupply
  ( Name(..)
  , Counter
  , NameSupplyState(..)
  , NameSupplyT(..)
  , runNameSupplyT
  , MonadNameSupply(..)
  ) where

import Control.Monad.RWS.Lazy
import Control.Monad.State.Lazy
import qualified Data.Text as T
import qualified Data.Map as M
import Data.Map (Map)
import Data.Maybe
import LLVM.Codegen.Name


type Counter = Int

data NameSupplyState
  = NameSupplyState
  { counter :: Counter
  , nameMap :: Map Name Counter
  }

newtype NameSupplyT m a
  = NameSupplyT (RWST (Maybe Name) () NameSupplyState m a)
  deriving (Functor, Applicative, Monad, MonadReader (Maybe Name), MonadState NameSupplyState, MonadFix, MonadIO)
  via RWST (Maybe Name) () NameSupplyState m

instance MonadTrans NameSupplyT where
  lift = NameSupplyT . lift

runNameSupplyT :: Monad m => NameSupplyT m a -> m a
runNameSupplyT (NameSupplyT m) =
  fst <$> evalRWST m Nothing (NameSupplyState 0 mempty)

class Monad m => MonadNameSupply m where
  fresh :: m Name
  named :: m a -> Name -> m a
  getSuggestion :: m (Maybe Name)

instance Monad m => MonadNameSupply (NameSupplyT m) where
  getSuggestion = ask

  fresh = getSuggestion >>= \case
    Nothing -> do
      count <- gets counter
      modify $ \s -> s { counter = count + 1 }
      pure $ Name $ T.pack (show count)
    Just suggestion -> do
      nameMapping <- gets nameMap
      let mCount = M.lookup suggestion nameMapping
          count = fromMaybe 0 mCount
      modify $ \s -> s { nameMap = M.insert suggestion (count + 1) nameMapping }
      pure $ Name $ unName suggestion <> "_" <> T.pack (show count)

  m `named` name =
    local (const $ Just name) m

instance MonadNameSupply m => MonadNameSupply (StateT s m) where
  getSuggestion = lift getSuggestion
  fresh = lift fresh
  named = flip $ (mapStateT . flip named)

-- TODO other instances, default signatures to reduce boilerplate