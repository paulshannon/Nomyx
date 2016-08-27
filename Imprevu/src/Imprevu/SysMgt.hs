
module Imprevu.SysMgt where

import           Control.Monad
import           Data.Time
import           System.Random

class (Monad n) => SysMgt n where
   currentTime     :: n UTCTime
   getRandomNumber :: Random a => (a, a) -> n a
