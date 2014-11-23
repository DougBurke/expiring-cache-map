{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module : Caching.ExpiringCacheMap.Internal
-- Copyright: (c) 2014 Edward L. Blake
-- License: BSD-style
-- Maintainer: Edward L. Blake <edwardlblake@gmail.com>
-- Stability: experimental
-- Portability: portable
--
-- A module with internal functions used in common by HashECM and OrdECM.
-- Assume these functions to change from version to version.
-- 

module Caching.ExpiringCacheMap.Internal.Internal (
    updateUses,
    detECM,
    getStatsString
) where

import qualified Data.List as L

import Caching.ExpiringCacheMap.Types
import Caching.ExpiringCacheMap.Internal.Types

updateUses :: (Eq k) => ([(k, ECMIncr)], ECMULength) -> k
  -> ECMIncr -> ECMULength -> ([(k, ECMIncr)] -> [(k, ECMIncr)])
    -> ([(k, ECMIncr)], ECMULength)
{-# INLINE updateUses #-}
updateUses uses id incr' compactlistsize compactUses =
    case uses of
        (((id', _) : rest), lcount) | id' == id ->
          (((id', incr') : rest), lcount)
        ((latest : (id', _) : rest), lcount) | id' == id ->
          (((id', incr') : latest : rest), lcount)
        ((latest : latest' : (id', _) : rest), lcount) | id' == id ->
          (((id', incr') : latest : latest' : rest), lcount)
        (usesl, lcount) ->
          if lcount > compactlistsize
            then let newusesl = compactUses usesl
                  in ((id, incr') : newusesl, (L.length newusesl) + 1)
            else ((id, incr') : usesl, lcount+1)

detECM
  :: (Monad m, Eq k) =>
     Maybe (TimeUnits, TimeUnits, v)
     -> m (TimeUnits, v)
     -> ((TimeUnits, TimeUnits, v) -> mp k (TimeUnits, TimeUnits, v))
     -> ((TimeUnits, TimeUnits, v) -> [(k, ECMIncr)] -> mp k (TimeUnits, TimeUnits, v))
     -> ([(k, ECMIncr)] -> [(k, ECMIncr)])
     -> m TimeUnits
     -> (((TimeUnits, TimeUnits, v) -> Bool)
         -> mp k (TimeUnits, TimeUnits, v) -> mp k (TimeUnits, TimeUnits, v))
     -> ([(k, ECMIncr)], ECMULength)
     -> ECMIncr
     -> ECMIncr
     -> mp k (TimeUnits, TimeUnits, v)
     -> ECMMapSize
     -> ECMULength
       -> m ((CacheState mp k v, v), Bool)
{-# INLINE detECM #-}
detECM result retr_id insert_id1 insert_id2 mnub gettime filt uses' incr' timecheckmodulo maps minimumkeep removalsize = 
    case result of
        Nothing -> do
          (expirytime, r) <- retr_id
          time <- gettime
          let (newmaps,newuses) = insertAndPerhapsRemoveSome time r expirytime uses'
          return $! ((CacheState (newmaps, newuses, incr'), r), False)
        Just (_accesstime, _expirytime, m) -> do
          if incr' `mod` timecheckmodulo == 0
            then do
              time <- gettime
              return ((CacheState (filterExpired time maps, uses', incr'), m), True)
            else return ((CacheState (maps, uses', incr'), m), False)
  where
  
    getKeepAndRemove =
      finalTup . splitAt minimumkeep . reverse . 
          sortI . map swap2 . mnub
        where swap2 (a,b) = (b,a)
              finalTup (l1,l2) = 
                (map (\(c,k) -> (k,c)) l1, map (\(c,k) -> k) l2)
              sortI = L.sortBy (\(l,_) (r,_) -> compare l r)
    
    insertAndPerhapsRemoveSome time r expirytime uses =
      if lcount >= removalsize
        then 
          let (keepuses, _removekeys) = getKeepAndRemove usesl
              newmaps = insert_id2 (time, expirytime, r) keepuses
           in (filterExpired time newmaps, (keepuses, L.length keepuses))
        else
          let newmaps = insert_id1 (time, expirytime, r)
           in (filterExpired time newmaps, uses)
      where
        (usesl, lcount) = uses
    
    filterExpired time =
      filt (\(accesstime, expirytime, value) ->
                 (accesstime <= time) &&
                   (accesstime > (time - expirytime)))


-- | Debugging function
--
getStatsString ecm = do
  CacheState (maps, uses, incr) <- ro m'uses
  return $ show uses
  where
    ECM ( m'uses, _retr, _gettime, _minimumkeep, _timecheckmodulo, _removalsize,
          _compactlistsize, _enter, ro ) = ecm

