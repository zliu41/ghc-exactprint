{-# LANGUAGE CPP #-}
{-# LANGUAGE ViewPatterns #-}
-- | Use "runhaskell Setup.hs test" or "cabal test" to run these tests.
module Main where

import Language.Haskell.GHC.ExactPrint
-- import Language.Haskell.Exts.Annotated
-- import qualified Language.Haskell.Exts as S -- S for "Simple", i.e. not annotated
import GHC.Paths ( libdir )
import qualified DynFlags      as GHC
import qualified FastString    as GHC
import qualified GHC           as GHC
-- import qualified GHC.Paths     as GHC
import qualified Lexer         as GHC
import qualified Name          as GHC
import qualified SrcLoc        as GHC
import qualified StringBuffer  as GHC
import qualified Unique        as GHC

import Test.Tasty hiding (defaultMain)
import Test.Tasty.Golden
import Test.Tasty.Golden.Manage
import System.FilePath
import System.FilePath.Find
import System.IO
import System.Directory
import Control.Monad
import Control.Monad.Trans
import Control.Applicative
import Data.Generics
-- import Extensions

main :: IO ()
main = do
  -- sources <- getTestFiles examplesDir
  sources2 <- getTestFiles examplesDir2
  defaultMain $ testGroup "Tests" $
    [ exactPrinterTests (sources2)
    ]

-- | Where all the tests are to be found
examplesDir :: FilePath
examplesDir = "tests" </> "examples"

examplesDir2 :: FilePath
examplesDir2 = "examples"

getTestFiles :: MonadIO m => FilePath -> m [FilePath]
getTestFiles dir = liftIO $ find (return True) (extension ==? ".hs" ||? extension ==? ".lhs") dir

exactPrinterTests :: [FilePath] -> TestTree -- {{{
exactPrinterTests sources = testGroup "Exact printer tests" $ do
  -- list monad
  file <- sources
  let
    out = file <.> "exactprinter" <.> "out"
    golden = file <.> "exactprinter" <.> "golden"
    run = do
      contents <- readUTF8File file
      (t,toks) <- parsedFileGhc file
      let
        parsed = GHC.pm_parsed_source $ GHC.tm_parsed_module t
        comments = toksToComments toks
        -- try to pretty-print; summarize the test result
        printed = exactPrint parsed comments
        result =
                if printed == contents
                  then "Match"
                  else printed
      writeBinaryFile out $ result ++ "\n"
  return $ goldenVsFile (takeBaseName file) golden out run
-- }}}


-- ---------------------------------------------------------------------
-- |Result of parsing a Haskell source file. It is simply the
-- TypeCheckedModule produced by GHC.
type ParseResult = GHC.TypecheckedModule

parsedFileGhc :: String -> IO (ParseResult,[(GHC.Located GHC.Token, String)])
parsedFileGhc fileName = do
#if __GLASGOW_HASKELL__ > 704
    GHC.defaultErrorHandler GHC.defaultFatalMessager GHC.defaultFlushOut $ do
#else
    GHC.defaultErrorHandler GHC.defaultLogAction $ do
#endif
      GHC.runGhc (Just libdir) $ do
        dflags <- GHC.getSessionDynFlags
        let dflags' = foldl GHC.xopt_set dflags
                           [GHC.Opt_Cpp, GHC.Opt_ImplicitPrelude, GHC.Opt_MagicHash]

            dflags'' = dflags' { GHC.importPaths = ["./test/testdata/","../test/testdata/"] }

            dflags''' = dflags'' { GHC.hscTarget = GHC.HscInterpreted,
                                   GHC.ghcLink =  GHC.LinkInMemory }

        void $ GHC.setSessionDynFlags dflags'''
        -- GHC.liftIO $ putStrLn $ "dflags set"

        target <- GHC.guessTarget fileName Nothing
        GHC.setTargets [target]
        -- GHC.liftIO $ putStrLn $ "targets set"
        void $ GHC.load GHC.LoadAllTargets -- Loads and compiles, much as calling make
        -- GHC.liftIO $ putStrLn $ "targets loaded"
        g <- GHC.getModuleGraph
        let showStuff ms = show (GHC.moduleNameString $ GHC.moduleName $ GHC.ms_mod ms,GHC.ms_location ms)
        -- GHC.liftIO $ putStrLn $ "module graph:" ++ (intercalate "," (map showStuff g))
        -- modSum <- GHC.getModSummary $ GHC.mkModuleName "BCpp"
        let modSum = head g
        p <- GHC.parseModule modSum
        t <- GHC.typecheckModule p
        -- GHC.liftIO $ putStrLn $ "parsed"
        toks <- GHC.getRichTokenStream (GHC.ms_mod modSum)
        return (t,toks)

readUTF8File :: FilePath -> IO String
readUTF8File fp = openFile fp ReadMode >>= \h -> do
        hSetEncoding h utf8
        hGetContents h


-- ---------------------------------------------------------------------

pwd :: IO FilePath
pwd = getCurrentDirectory

cd :: FilePath -> IO ()
cd = setCurrentDirectory

