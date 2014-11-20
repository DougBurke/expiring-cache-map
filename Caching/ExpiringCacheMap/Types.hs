{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module : Caching.ExpiringCacheMap.Types
-- Copyright: (c) 2014 Edward L. Blake
-- License: BSD-style
-- Maintainer: Edward L. Blake <edwardlblake@gmail.com>
-- Stability: experimental
-- Portability: portable
--
-- Types for expiring cache maps.
-- 

module Caching.ExpiringCacheMap.Types (
    TimeUnits,
    ECMULength,
    ECMIncr,
    ECM
) where

import qualified Control.Concurrent.MVar as MV
import Data.Word (Word32)

type TimeUnits = Int
type ECMULength = Int
type ECMIncr = Word32
type ECM m k v = ( MV.MVar (m k (TimeUnits, v), ([(k, ECMIncr)], ECMULength), ECMIncr),
                  k -> IO v,
                  IO TimeUnits,
                  Int,
                  TimeUnits,
                  ECMIncr,
                  ECMULength,
                  ECMULength)
