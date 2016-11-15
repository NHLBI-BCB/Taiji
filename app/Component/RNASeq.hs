--------------------------------------------------------------------------------
-- RNA-seq data processing
--------------------------------------------------------------------------------
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Component.RNASeq (builder) where

import           Bio.Data.Experiment.Types
import           Bio.Pipeline.NGS
import           Bio.RealWorld.GENCODE
import           Bio.Utils.Misc                    (readDouble)
import           Control.Arrow                     (second)
import           Control.Lens
import           Control.Monad                     (forM)
import           Control.Monad.IO.Class            (liftIO)
import qualified Data.ByteString.Char8             as B
import           Data.CaseInsensitive              (original)
import           Data.Double.Conversion.ByteString (toShortest)
import qualified Data.HashMap.Strict               as M
import           Data.List
import           Data.List.Ordered                 (nubSort)
import           Data.Maybe                        (fromJust, mapMaybe)
import qualified Data.Text                         as T
import           Scientific.Workflow

import           Constants

builder :: Builder ()
builder = do
    node "Get_RNA_data" [| return . (^._3) |] $ do
        submitToRemote .= Just False
        label .= "Get RNA-seq data"
    node "RNA_alignment" [| \x -> starAlign <$> rnaOutput <*> getConfig' "starIndex" <*>
            return (starCores .= 4) <*> return x >>= liftIO
        |] $ batch .= 1 >> stateful .= True >> remoteParam .= "-l vmem=10G -pe smp 4"
    node "RNA_quantification" [| \x ->
        rsemQuant <$> rnaOutput <*> fmap fromJust rsemIndex <*>
            return (rsemCores .= 4) <*> return x >>= liftIO
        |] $ batch .= 1 >> stateful .= True >> remoteParam .= "-l vmem=10G -pe smp 4"
    node "Output_expression" [| \x ->
        combineExpression <$> fmap (++"/gene_expression.tsv") rnaOutput <*>
            getConfig' "annotation" <*> return x >>= liftIO
        |] $ stateful .= True
    path [ "Initialization", "Get_RNA_data", "RNA_alignment"
         , "RNA_quantification", "Output_expression" ]

-- | Combine RNA expression data into a table
combineExpression :: FilePath
                  -> FilePath   -- ^ annotation in GTF format
                  -> [RNASeq]
                  -> IO (Maybe FilePath)
combineExpression output anno es
    | null es = return Nothing
    | otherwise = do
        id2Name <- fmap (M.fromList . map (\x -> (geneId x, original $ geneName x))) $
            readGenes' anno
        dat <- forM es $ \e -> do
            let fls = e^..replicates.folded.files.folded._Single.
                    filtered (elem "gene quantification" . (^.keywords))
            expr <- mapM (readExpr . (^.location)) fls
            return (fromJust $ e^.groupName, map (second average) $ combine expr)
        let (expNames, values) = unzip dat
        B.writeFile output $ B.unlines $
            (B.pack $ T.unpack $ T.intercalate "\t" $ "Name" : expNames) :
            (map (\(x,xs) -> B.intercalate "\t" $
            M.lookupDefault (error $ show x) x id2Name :
            map toShortest xs) $ combine values)
        return $ Just output
  where
    combine xs = flip map names $ \nm -> (nm, map (M.lookupDefault 0.01 nm) xs')
      where
        names = nubSort $ concatMap (fst . unzip) xs
        xs' = map M.fromList xs
    readExpr fl = do
        c <- B.readFile fl
        return $ map ((\xs -> (head xs, readDouble $ xs!!4)) . B.split '\t') $
            tail $ B.lines c
    average xs = foldl' (+) 0 xs / fromIntegral (length xs)
