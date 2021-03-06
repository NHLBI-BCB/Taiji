-- Call Peaks using IDR framework
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Taiji.Component.ATACSeq.CallPeak.MACS2 (builder) where

import           Bio.Data.Experiment.Types
import           Bio.Data.Experiment.Utils
import           Bio.Pipeline.CallPeaks
import           Bio.Pipeline.Utils (mapOfFiles)
import           Control.Lens
import           Control.Monad.IO.Class    (liftIO)
import qualified Data.Text                 as T
import           Scientific.Workflow

import           Taiji.Constants

builder :: Builder ()
builder = do
    node "ATAC_MACS_prepare" [| return . mergeExps |] $ do
        submitToRemote .= Just False
        note .= "Prepare for MACS2 peak calling."

    node "ATAC_callpeaks" [| mapOfFiles $ \e r fl -> do
        dir <- atacOutput
        if r^.number /= 0 || not (formatIs BedGZip fl || formatIs BedFile fl)
            then return []
            else do
                let output = printf "%s/%s_rep%d_MACS.narrowPeak" dir
                        (T.unpack $ e^.eid) (r^.number)
                result <- liftIO $ callPeaks output fl Nothing $ pair .= pairedEnd e
                return [result]
        |] $ do
            batch .= 1
            stateful .= True
            note .= "Call narrow peaks using MACS2. Default options: \"--qvalue 0.01 --keep-dup all\"."
    path ["ATAC_callpeaks_prepare", "ATAC_MACS_prepare", "ATAC_callpeaks"]
