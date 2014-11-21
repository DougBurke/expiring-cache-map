{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module : Caching.ExpiringCacheMap.OrdECM
-- Copyright: (c) 2014 Edward L. Blake
-- License: BSD-style
-- Maintainer: Edward L. Blake <edwardlblake@gmail.com>
-- Stability: experimental
-- Portability: portable
--
-- A cache that holds values for a length of time that uses 'Ord' keys with 
-- "Data.Map.Strict".
-- 

module Caching.ExpiringCacheMap.OrdECM (
    -- * Create cache
    -- newECMIO,
    newECM,
    
    -- * Request value from cache
    getECM,
    
    -- * Type
    ECM,
    
    -- * Miscellaneous
    getStats
) where

import qualified Control.Concurrent.MVar as MV
import qualified Data.Map.Strict as M
import qualified Data.List as L

import Caching.ExpiringCacheMap.Internal (updateUses)
import Caching.ExpiringCacheMap.Types

-- | Creates a new expiring cache for the common usage case of retrieving
-- uncached values via 'IO' interaction (such as in the case of reading 
-- a file from disk), with a shared state lock via an 'MV.MVar' to manage
-- cache state.
--
newECM :: Ord k => (k -> IO v) -> (IO TimeUnits) -> Int -> Int -> ECMIncr -> ECMULength -> IO (ECM IO MV.MVar M.Map k v)
newECM retr gettime minimumkeep expirytime timecheckmodulo removalsize = do
  m'maps <- MV.newMVar $ CacheState ( M.empty, ([], 0), 0 )
  return $ ECM (m'maps, retr, gettime, minimumkeep, expirytime, timecheckmodulo, removalsize, removalsize*2, MV.modifyMVar, MV.readMVar)

-- | Request a value associated with a key from the cache.
--
--  * If the value is not in the cache, it will be requested through the 
--    function defined through 'newECM', its computation returned and the
--    value stored in the cache state map.
--
--  * If the value is in the cache, the modulo of the cache accumulator and
--    the modulo value equates to 0 which causes a time request with the
--    function defined through 'newECM', and the value has been determined
--    to have since expired, it will be returned regardless for this 
--    computation and the key will be removed along with other expired
--    values from the cache state map.
--
--  * If the value is in the cache and has not expired, it will be returned.
--
-- Every getECM computation increments an accumulator in the cache state which 
-- is used to keep track of the succession of key accesses. This history of
-- key accesses is then used to remove entries from the cache back down to a
-- minimum size. Also, when the modulo of the accumulator and the modulo value 
-- computes to 0, the time request function defined with 'newECM' is invoked 
-- for the current time to update which if any of the entries in the internal 
-- map needs to be removed.
--
-- As the accumulator is a bound unsigned integer, when the accumulator 
-- increments back to 0, the cache state is completely cleared.
-- 
getECM :: (Monad m, Ord k) => ECM m mv M.Map k v -> k -> m v
getECM ecm id = do
  enter m'maps $
    \(CacheState (maps, uses, incr)) ->
      let incr' = incr + 1
       in if incr' < incr
            -- Word incrementor has cycled back to 0,
            -- so may as well clear the cache completely.
            then getECM' (M.empty, ([], 0), 0) (0+1)
            else getECM' (maps, uses, incr) incr'
  where
    
    getECM' (maps, uses, incr) incr' = do
      let uses' = updateUses uses id incr' compactlistsize (M.toList . M.fromList . reverse)
      case M.lookup id maps of
        Nothing -> do
          r <- retr id
          time <- gettime
          let (newmaps,newuses) = insertAndPerhapsRemoveSome id time r maps uses'
          return $! (CacheState (newmaps, newuses, incr'), r)
        Just (accesstime, m) -> do
          if incr' `mod` timecheckmodulo == 0
            then do
              time <- gettime
              return (CacheState (filterExpired time maps, uses', incr'), m)
            else return (CacheState (maps, uses', incr'), m)
    
    ECM (m'maps, retr, gettime, minimumkeep, expirytime, timecheckmodulo, removalsize, compactlistsize, enter, _ro) = ecm
    
    getKeepAndRemove =
      finalTup . splitAt minimumkeep . reverse . 
          sortI . map swap2 . M.toList . M.fromList . reverse
        where swap2 (a,b) = (b,a)
              finalTup (l1,l2) = 
                (map (\(c,k) -> (k,c)) l1, map (\(c,k) -> k) l2)
              sortI = L.sortBy (\(l,_) (r,_) -> compare l r)
    
    insertAndPerhapsRemoveSome id time r maps uses =
      if lcount >= removalsize
        then 
          let (keepuses, _removekeys) = getKeepAndRemove usesl
              newmaps = M.insert id (time, r) $! M.intersection maps $ M.fromList keepuses
           in (filterExpired time newmaps, (keepuses, L.length keepuses))
        else
          let newmaps = M.insert id (time, r) maps
           in (filterExpired time newmaps, uses)
      where
        (usesl, lcount) = uses
    
    filterExpired time =
      M.filter (\(accesstime, value) ->
                 (accesstime <= time) &&
                   (accesstime > (time - expirytime)))

--
--
--
getStats ecm = do
  CacheState (maps, uses, incr) <- ro m'uses
  return uses
  where
    ECM (m'uses, retr, gettime, minimumkeep, expirytime, timecheckmodulo, removalsize, compactlistsize, _enter, ro) = ecm