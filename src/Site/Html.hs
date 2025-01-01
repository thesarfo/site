-- | The page shell and the small pieces every page shares.
module Site.Html
  ( Page (..)
  , defaultPage
  , page
  , siteUrl
  , formatDate
  , percentEncode
  , fadeIn
  , backLink
  , sectionHeader
  , dateGrid
  , icon
  ) where

import Data.Char (isAlphaNum, ord)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Data.Time (defaultTimeLocale, formatTime, parseTimeM)
import Data.Time.Calendar (Day)
import Numeric (showHex)
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A
import Text.Blaze.Internal (preEscapedText)

siteUrl :: Text
siteUrl = "https://www.thesarfo.com"

data Page = Page
  { pgTitle :: Text
  , pgDescription :: Text
  , pgPath :: Text -- ^ canonical path, e.g. "/writing/gfs"
  , pgNav :: Maybe Text -- ^ which nav link is lit, e.g. "/writing"
  , pgType :: Text -- ^ og:type
  , pgImage :: Maybe Text -- ^ site-relative image for link previews
  , pgHead :: Html -- ^ extra tags for <head>
  }

defaultPage :: Page
defaultPage =
  Page
    { pgTitle = "Ernest Sarfo"
    , pgDescription = "A programmer from Ghana (🇬🇭) who likes to build software that doesn't suck. I share my thoughts on software engineering and systems design."
    , pgPath = "/"
    , pgNav = Nothing
    , pgType = "website"
    , pgImage = Nothing
    , pgHead = mempty
    }

navLinks :: [(Text, Text)]
navLinks = [("/writing", "Writing"), ("/shelf", "Shelf"), ("/now", "Now")]

-- | "2026-10-05" -> "October 5, 2026". Anything that is not a date is shown as written.
formatDate :: String -> String
formatDate s = case parseTimeM True defaultTimeLocale "%Y-%m-%d" (take 10 s) :: Maybe Day of
  Just d -> formatTime defaultTimeLocale "%B %-d, %Y" d
  Nothing -> s

-- | RFC 3986 percent-encoding, for share links.
percentEncode :: Text -> Text
percentEncode = T.concatMap enc
  where
    enc c
      | isAlphaNum c && ord c < 128 = T.singleton c
      | c `elem` ("-._~" :: String) = T.singleton c
      | otherwise = T.concat [T.pack ('%' : pad (showHex b "")) | b <- utf8 c]
    pad h = if length h < 2 then '0' : h else h
    utf8 c = BS.unpack (encodeUtf8 (T.singleton c))

fadeIn :: Int -> H.Attribute
fadeIn n = A.class_ (H.toValue (T.unwords ("fade" : [T.pack ('d' : show n) | n > 0])))

backLink :: Text -> Text -> Html
backLink href label =
  H.a ! A.href (H.toValue href) ! A.class_ "back" $ do
    H.toHtml ("← " :: Text)
    H.toHtml label

sectionHeader :: Text -> Text -> Html
sectionHeader title to =
  H.div ! A.class_ "section-head" $ do
    H.h2 ! A.class_ "mono-label" $ H.toHtml title
    H.a ! A.href (H.toValue to) ! A.class_ "all-link" $ "All →"

-- | Two-column rows: a muted date on the left, a link on the right.
dateGrid :: Bool -> [(String, Html)] -> Html
dateGrid roomy rows =
  H.div ! A.class_ (if roomy then "date-grid roomy" else "date-grid") $
    mapM_ (\(when', body) -> H.time (H.toHtml when') >> body) rows

-- | Inline SVG icons (Lucide paths).
icon :: Text -> Html
icon name = case name of
  "sun" -> svg "<circle cx=\"12\" cy=\"12\" r=\"4\"/><path d=\"M12 2v2M12 20v2m-7.07-15.07 1.41 1.41m11.32 11.32 1.41 1.41M2 12h2m16 0h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41\"/>"
  "moon" -> svg "<path d=\"M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z\"/>"
  "system" -> svg "<rect width=\"20\" height=\"14\" x=\"2\" y=\"3\" rx=\"2\"/><path d=\"M8 21h8M12 17v4\"/>"
  _ -> mempty
  where
    svg inner =
      preEscapedText ("<svg viewBox=\"0 0 24 24\" aria-hidden=\"true\">" <> inner <> "</svg>")

themeToggle :: Html
themeToggle =
  H.div ! A.class_ "theme-toggle" ! H.customAttribute "role" "group" ! H.customAttribute "aria-label" "Theme" $ do
    btn "system" "Use system theme"
    btn "dark" "Use dark theme"
    btn "light" "Use light theme"
  where
    btn :: Text -> Text -> Html
    btn mode label =
      H.button
        ! A.type_ "button"
        ! H.dataAttribute "theme" (H.toValue mode)
        ! H.customAttribute "aria-label" (H.toValue label)
        ! H.customAttribute "aria-pressed" "false"
        $ icon (if mode == "dark" then "moon" else if mode == "light" then "sun" else "system")

-- | Wrap a page body in the site shell.
page :: Page -> Html -> Html
page pg body = H.docTypeHtml ! A.lang "en" $ do
  H.head $ do
    H.meta ! A.charset "UTF-8"
    H.meta ! A.name "viewport" ! A.content "width=device-width, initial-scale=1.0"
    H.link ! A.rel "icon" ! A.type_ "image/svg+xml" ! A.href "/favicon.svg"
    H.title (H.toHtml fullTitle)
    H.meta ! A.name "description" ! A.content (H.toValue (pgDescription pg))
    H.meta ! A.name "author" ! A.content "Ernest Sarfo"
    H.link ! A.rel "canonical" ! A.href (H.toValue url)

    og "og:title" fullTitle
    og "og:description" (pgDescription pg)
    og "og:type" (pgType pg)
    og "og:url" url
    og "og:site_name" "Ernest Sarfo"
    mapM_ (\i -> og "og:image" (siteUrl <> i)) (pgImage pg)
    H.meta ! A.name "twitter:card" ! A.content (if hasImage then "summary_large_image" else "summary")
    H.meta ! A.name "twitter:title" ! A.content (H.toValue fullTitle)
    H.meta ! A.name "twitter:description" ! A.content (H.toValue (pgDescription pg))
    mapM_ (\i -> H.meta ! A.name "twitter:image" ! A.content (H.toValue (siteUrl <> i))) (pgImage pg)

    H.link ! A.rel "preconnect" ! A.href "https://fonts.googleapis.com"
    H.link ! A.rel "preconnect" ! A.href "https://fonts.gstatic.com" ! H.customAttribute "crossorigin" ""
    H.link
      ! A.href "https://fonts.googleapis.com/css2?family=Barlow:wght@400;500&family=Instrument+Serif:ital@0;1&family=Mansalva&display=swap"
      ! A.rel "stylesheet"
    H.link ! A.rel "preload" ! A.href "/fonts/departure-mono.woff2" ! H.customAttribute "as" "font" ! A.type_ "font/woff2" ! H.customAttribute "crossorigin" ""

    -- Apply the stored theme before first paint.
    H.script $
      preEscapedText
        "(function(){try{var s=localStorage.getItem('theme');var t=(s==='dark'||s==='light')?s:(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');document.documentElement.classList.add(t);}catch(e){}})();"

    H.link ! A.rel "stylesheet" ! A.href "/site.css"
    H.link ! A.rel "stylesheet" ! A.href "/syntax.css"
    pgHead pg

    H.script ! A.async "" ! A.src "https://www.googletagmanager.com/gtag/js?id=G-93F53HK5DQ" $ mempty
    H.script $
      preEscapedText
        "window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}gtag('js',new Date());gtag('config','G-93F53HK5DQ');"
  H.body $ do
    H.div ! A.class_ "shell" $ do
      H.header ! A.class_ "site-header" $
        H.nav ! A.class_ "nav" $ do
          H.a ! A.href "/" ! A.class_ "brand" $ "Ernest Sarfo"
          H.div ! A.class_ "nav-right" $ do
            H.ul ! A.class_ "nav-links" $
              mapM_ navItem navLinks
            themeToggle
      H.main $ H.div ! A.class_ "wrap" $ body
      H.footer ! A.class_ "site-footer" $
        H.div ! A.class_ "wrap" $ do
          H.div $ do
            H.p ! A.class_ "tag" $ "Stay shady."
            H.p "© Ernest Sarfo"
          H.div ! A.class_ "footer-links" $ do
            H.a ! A.href "/lens" $ "lens"
            H.a ! A.href "/renders" $ "renders"
    H.script ! A.src "/site.js" ! A.defer "" $ mempty
  where
    hasImage = pgImage pg /= Nothing
    fullTitle = if pgTitle pg == "Ernest Sarfo" then pgTitle pg else pgTitle pg <> ", Ernest Sarfo"
    url = siteUrl <> (if pgPath pg == "/" then "" else pgPath pg)
    og :: Text -> Text -> Html
    og prop content = H.meta ! H.customAttribute "property" (H.toValue prop) ! A.content (H.toValue content)
    navItem (path, label) =
      H.li $
        H.a
          ! A.href (H.toValue path)
          ! A.class_ (if pgNav pg == Just path then "nav-link active" else "nav-link")
          $ H.toHtml label
