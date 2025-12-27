module Main (main) where

import Control.Monad (forM_)
import Data.Aeson (FromJSON, eitherDecode)
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (isJust)
import qualified Data.Text as T
import Hakyll
import Site.Markdown
import Site.Types
import Site.Pages.Home (home)
import Site.Pages.Writing (postPage, writingIndex)
import Site.Pages.Papers (paperPage, papersPage)
import Site.Pages.Now (nowPage)
import Site.Pages.Lens (lensPage)
import Site.Pages.NotFound (notFoundPage)
import System.Environment (lookupEnv)
import System.FilePath (takeBaseName, takeDirectory, takeFileName)
import Text.Blaze.Html.Renderer.String (renderHtml)
import Text.Blaze.Html5 (Html)

config :: Configuration
config =
  defaultConfiguration
    { providerDirectory = "site"
    , destinationDirectory = "_site"
    , storeDirectory = "_cache"
    , tmpDirectory = "_cache/tmp"
    }

main :: IO ()
main = do
  -- Unpublished posts carry `draft: true`. Set DRAFTS=1 to preview them locally.
  showDrafts <- isJust <$> lookupEnv "DRAFTS"
  hakyllWith config (rules showDrafts)

rules :: Bool -> Rules ()
rules showDrafts = do
  -- Everything under static/ is served from the site root.
  match "static/**" $ do
    route (gsubRoute "static/" (const ""))
    compile copyFileCompiler

  match "assets/*.js" $ do
    route (gsubRoute "assets/" (const ""))
    compile copyFileCompiler

  match "assets/*.css" $ do
    route (gsubRoute "assets/" (const ""))
    compile compressCssCompiler

  create ["syntax.css"] $ do
    route idRoute
    compile (makeItem syntaxCss)

  -- JSON data is loaded through the compiler so edits trigger rebuilds.
  match "data/*.json" $ compile getResourceLBS

  -- Posts.
  matchMetadata "content/writing/*.md" (publishable showDrafts) $ do
    route (pageRoute "writing")
    compile $ do
      ident <- getUnderlying
      posts <- allPosts showDrafts
      serieses <- loadData "data/series.json"
      post <- postFor ident
      body <- renderMarkdown Prose =<< getResourceBody
      makeItem (renderHtml (postPage serieses posts post (itemBody body)))

  create ["writing/index.html"] $ do
    route idRoute
    compile $ allEntries showDrafts >>= html . writingIndex

  create ["index.html"] $ do
    route idRoute
    compile $ do
      entries <- allEntries showDrafts
      projects <- loadData "data/projects.json"
      papers <- loadData "data/papers.json"
      quotes <- loadData "data/quotes.json"
      html (home entries projects papers quotes)

  -- Papers: three to a page, and one page per paper.
  papersRules

  create ["now/index.html"] $ staticPage nowPage

  create ["lens/index.html"] $ staticPage lensPage

  create ["404.html"] $ staticPage notFoundPage

papersRules :: Rules ()
papersRules = do
  rawPapers <- preprocess (BL.readFile "site/data/papers.json")
  case eitherDecode rawPapers :: Either String [Paper] of
    Left err -> fail ("papers.json: " ++ err)
    Right papers -> do
      let chunks = chunk 3 papers
      forM_ (zip [1 ..] chunks) $ \(n, ps) ->
        create [fromFilePath (if n == (1 :: Int) then "papers/index.html" else "papers/page/" ++ show n ++ "/index.html")] $ do
          route idRoute
          compile $ do
            _ <- load (fromFilePath "data/papers.json") :: Compiler (Item BL.ByteString)
            html (papersPage n (length chunks) ps)
      forM_ papers $ \p ->
        create [fromFilePath ("papers/" ++ T.unpack (paperSlug p) ++ "/index.html")] $ do
          route idRoute
          compile $ do
            _ <- load (fromFilePath "data/papers.json") :: Compiler (Item BL.ByteString)
            html (paperPage p)

-- ---------------------------------------------------------------------------

html :: Html -> Compiler (Item String)
html = makeItem . renderHtml

staticPage :: Html -> Rules ()
staticPage h = do
  route idRoute
  compile (html h)

chunk :: Int -> [a] -> [[a]]
chunk _ [] = []
chunk n xs = let (a, b) = splitAt n xs in a : chunk n b

loadData :: FromJSON a => Identifier -> Compiler a
loadData ident = do
  Item _ bytes <- load ident :: Compiler (Item BL.ByteString)
  either (\err -> fail (toFilePath ident ++ ": " ++ err)) pure (eitherDecode bytes)

-- | content/writing/foo.md -> writing/foo/index.html
pageRoute :: String -> Routes
pageRoute dir = customRoute $ \ident -> dir ++ "/" ++ takeBaseName (toFilePath ident) ++ "/index.html"

publishable :: Bool -> Metadata -> Bool
publishable showDrafts meta = showDrafts || lookupString "draft" meta `notElem` [Just "true"]

postFromMeta :: Identifier -> Metadata -> Post
postFromMeta ident meta =
  Post
    { postSlug = takeBaseName (toFilePath ident)
    , postTitle = textField "title"
    , postDate = textField "date"
    , postExcerpt = textField "excerpt"
    , postImage = lookupString "image" meta
    , postSeries = case (lookupString "series" meta, lookupString "part" meta) of
        (Just sid, Just n) -> Just (sid, read n)
        _ -> Nothing
    }
  where
    textField k = maybe "" id (lookupString k meta)

postFor :: Identifier -> Compiler Post
postFor ident = postFromMeta ident <$> getMetadata ident

allPosts :: Bool -> Compiler [Post]
allPosts showDrafts = do
  metas <- getAllMetadata "content/writing/*.md"
  pure [postFromMeta i m | (i, m) <- metas, publishable showDrafts m]

allEntries :: Bool -> Compiler [Entry]
allEntries showDrafts = do
  posts <- allPosts showDrafts
  serieses <- loadData "data/series.json"
  pure (writingEntries serieses posts)
