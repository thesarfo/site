-- | Markdown to HTML through pandoc, with the same reading rules the old site had:
-- CommonMark plus GFM-style tables, strikethrough and task lists, no smart quotes,
-- no auto-captioned figures, and `$...$` math only where a page asks for it.
module Site.Markdown
  ( Flavour (..)
  , renderMarkdown
  , syntaxCss
  ) where

import qualified Data.Text as T
import Hakyll (Compiler, Item, itemBody, makeItem)
import Text.Pandoc
import Text.Pandoc.Format (parseFlavoredFormat)
import Text.Pandoc.Highlighting (breezeDark, pygments, styleToCss)
import Text.Pandoc.Walk (walk)

data Flavour = Prose | Notes
  deriving (Eq)

-- | `Prose` is a post (math on); `Notes` is a book chapter (a `$` is just a dollar sign).
renderMarkdown :: Flavour -> Item String -> Compiler (Item String)
renderMarkdown flavour item =
  case runPure (convert flavour (T.pack (itemBody item))) of
    Left err -> fail ("pandoc: " ++ show err)
    Right html -> makeItem (T.unpack html)

convert :: PandocMonad m => Flavour -> T.Text -> m T.Text
convert flavour src = do
  flavored <- parseFlavoredFormat "commonmark_x"
  (reader, exts) <- getReader flavored
  let wanted = case flavour of
        Prose -> id
        Notes -> disableExtension Ext_tex_math_dollars
      readerOpts =
        def
          { readerExtensions =
              wanted (disableExtension Ext_implicit_figures (disableExtension Ext_smart exts))
          }
      writerOpts =
        def
          { writerMathMethod = MathML
          , writerHighlightMethod = Skylighting pygments
          , writerExtensions = disableExtension Ext_smart (writerExtensions def)
          }
  doc <- case reader of
    TextReader r -> r readerOpts src
    ByteStringReader _ -> error "commonmark_x is a text reader"
  writeHtml5String writerOpts (walk tidyInline doc)

-- | External links open in a new tab, images load lazily, and image paths that pointed
-- into the old repo's public/ folder point at the site root instead.
tidyInline :: Inline -> Inline
tidyInline (Link (i, cs, kvs) body (url, title))
  | isExternal url =
      Link (i, cs, kvs ++ [("target", "_blank"), ("rel", "noopener noreferrer")]) body (url, title)
tidyInline (Image (i, cs, kvs) body (url, title)) =
  Image (i, cs, kvs ++ [("loading", "lazy")]) body (fixSrc url, title)
tidyInline other = other

isExternal :: T.Text -> Bool
isExternal u = "http://" `T.isPrefixOf` u || "https://" `T.isPrefixOf` u

fixSrc :: T.Text -> T.Text
fixSrc u = case T.breakOn "public/" u of
  (before, rest)
    | not (T.null rest) && T.all (`elem` ("./" :: String)) before -> "/" <> T.drop 7 rest
  _ -> u

-- | Token colours for highlighted code, scoped by theme class. Block layout lives in site.css.
syntaxCss :: String
syntaxCss = unlines (scoped "html:not(.dark)" (styleToCss pygments) ++ scoped "html.dark" (styleToCss breezeDark))
  where
    scoped prefix css = [prefix ++ " " ++ l | l <- lines css, "code span" `isPrefix` l]
    isPrefix p s = take (length p) s == p
