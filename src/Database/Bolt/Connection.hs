module Database.Bolt.Connection where

import           Database.Bolt.Connection.Pipe
import           Database.Bolt.Connection.Instances
import           Database.Bolt.Connection.Type
import           Database.Bolt.Value.Instances
import           Database.Bolt.Value.Type
import           Database.Bolt.Record

import           Control.Monad                 (void, when)
import           Control.Monad.IO.Class        (MonadIO (..))
import           Control.Monad.Trans.Reader    (ReaderT (..), ask, runReaderT)
import           Data.Text                     (Text)
import           Data.Map.Strict               (empty)

-- |Monad Transformer to do all BOLT actions in
type BoltActionT = ReaderT Pipe

-- |Runs BOLT action on selected pipe
run :: MonadIO m => Pipe -> BoltActionT m a -> m a
run = flip runReaderT

-- |Runs Cypher query and returns list of obtained 'Record's
query :: MonadIO m => Text -> BoltActionT m [Record]
query cypher = toRecords <$> pullRequests
  where pullRequests :: MonadIO m => BoltActionT m [Response]
        pullRequests = do pipe <- ask
                          let request = RequestRun cypher empty
                          flush pipe request
                          status <- fetch pipe
                          if isSuccess status then do flush pipe RequestPullAll
                                                      (status:) <$> pullRest pipe
                                              else do ackFailure pipe
                                                      return [status]

        pullRest :: MonadIO m => Pipe -> m [Response]
        pullRest pipe = do resp <- fetch pipe
                           if isSuccess resp then return [resp]
                                             else (resp:) <$> pullRest pipe

-- |Runs Cypher query and ignores response
query_ :: MonadIO m => Text -> BoltActionT m ()
query_ cypher = do pipe <- ask
                   flush pipe (createRun cypher)
                   status <- fetch pipe
                   when (isFailure status) $
                     ackFailure pipe
                   when (isSuccess status) $
                     discardAll pipe
