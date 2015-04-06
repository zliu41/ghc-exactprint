
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
module Common where

import Language.Haskell.GHC.ExactPrint
import Language.Haskell.GHC.ExactPrint.Transform
import Language.Haskell.GHC.ExactPrint.Utils

import GHC.Paths (libdir)

import qualified DynFlags      as GHC
import qualified FastString    as GHC
import qualified Outputable    as GHC
import qualified RdrName       as GHC
import qualified StringBuffer  as GHC
import qualified HeaderInfo  as GHC
import qualified SrcLoc  as GHC
import qualified Parser  as GHC
import qualified Lexer  as GHC
import qualified ApiAnnotation  as GHC
import qualified HsSyn  as GHC
import qualified GHC  as GHC hiding (parseModule)

import qualified Data.Map as Map

import qualified Data.Text.IO as T
import qualified Data.Text as T

import Data.List hiding (find)

import Test.HUnit


-- Roundtrip machinery



data Report =
   Success
 | ParseFailure GHC.SrcSpan GHC.SDoc
 | RoundTripFailure String
 | CPP


instance Show Report where
  show Success = "Success"
  show (ParseFailure _ s) = "ParseFailure: " ++ GHC.showSDocUnsafe s
  show (RoundTripFailure _) = "RoundTripFailure"
  show (CPP)              = "CPP"

runParser :: GHC.P a -> GHC.DynFlags -> FilePath -> String -> GHC.ParseResult a
runParser parser flags filename str = GHC.unP parser parseState
    where
      location = GHC.mkRealSrcLoc (GHC.mkFastString filename) 1 1
      buffer = GHC.stringToStringBuffer str
      parseState = GHC.mkPState flags buffer location

parseFile :: GHC.DynFlags -> FilePath -> String -> GHC.ParseResult (GHC.Located (GHC.HsModule GHC.RdrName))
parseFile = runParser GHC.parseModule

mkApiAnns :: GHC.PState -> GHC.ApiAnns
mkApiAnns pstate = (Map.fromListWith (++) . GHC.annotations $ pstate
                   , Map.fromList ((GHC.noSrcSpan, GHC.comment_q pstate) : (GHC.annotations_comments pstate)))

getDynFlags :: IO GHC.DynFlags
getDynFlags =
  GHC.defaultErrorHandler GHC.defaultFatalMessager GHC.defaultFlushOut $
    GHC.runGhc (Just libdir) GHC.getSessionDynFlags


roundTripTest :: FilePath -> IO Report
roundTripTest file = do
  dflags0 <- getDynFlags
  let dflags1 = GHC.gopt_set dflags0 GHC.Opt_KeepRawTokenStream
  src_opts <- GHC.getOptionsFromFile dflags1 file
  (!dflags2, _, _)
           <- GHC.parseDynamicFilePragma dflags1 src_opts
  if GHC.xopt GHC.Opt_Cpp dflags2
    then return $ CPP
    else do
      contents <- T.unpack <$> T.readFile file
      case parseFile dflags2 file contents of
        GHC.PFailed ss m -> return $ ParseFailure ss m
        GHC.POk s pmod   -> do
          let (printed, anns) = runRoundTrip (mkApiAnns s) pmod
              debugtxt = mkDebugOutput file printed contents (mkApiAnns s) anns pmod
          if printed == contents
            then return Success
            else do
              return $ RoundTripFailure debugtxt



mkDebugOutput :: FilePath -> String -> String
              -> GHC.ApiAnns
              -> Anns
              -> GHC.Located (GHC.HsModule GHC.RdrName) -> String
mkDebugOutput filename printed original apianns anns parsed =
  intercalate sep [ printed
                 , filename
                 , "lengths:" ++ show (length printed,length original) ++ "\n"
                 , showAnnData anns 0 parsed
                 , showGhc anns
                 , showGhc apianns
                ]
  where
    sep = "\n==============\n"


runRoundTrip :: GHC.ApiAnns -> GHC.Located (GHC.HsModule GHC.RdrName)
              -> (String, Anns)
runRoundTrip !anns !parsedOrig =
  let
    (!_, !parsed) = fixBugsInAst anns parsedOrig
    !relAnns = relativiseApiAnns parsedOrig anns
    !printed = exactPrintWithAnns parsed relAnns
  in (printed,  relAnns)
