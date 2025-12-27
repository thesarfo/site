-- | The writing list and a single post.
module Site.Pages.Writing
  ( writingIndex
  , postPage
  ) where

import qualified Data.Text as T
import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A
import Text.Blaze.Internal (preEscapedText)

writingIndex :: [Entry] -> Html
writingIndex entries =
  page defaultPage {pgTitle = "Writing", pgDescription = "Thoughts on engineering & whatever else I'm trying to understand.", pgPath = "/writing", pgNav = Just "/writing"} $
    pageSection $ do
      title1 "Writing"
      ledeP "Thoughts on engineering & whatever else I'm trying to understand."
      H.div ! A.class_ "fade d2" $
        dateGrid True
          [ (formatDate (entryDate e), H.a ! A.href (v (postHref (entrySlug e))) ! A.class_ "entry-link" $ s (entryTitle e))
          | e <- entries
          ]

postPage :: [Series] -> [Post] -> Post -> String -> Html
postPage serieses posts post body =
  page
    defaultPage
      { pgTitle = T.pack (maybe (postTitle post) (\(sr, n) -> seriesTitle sr ++ ", part " ++ show n ++ ": " ++ postTitle post) (postSeries post))
      , pgDescription = T.pack (postExcerpt post)
      , pgPath = postHref (postSlug post)
      , pgType = "article"
      , pgImage = T.pack <$> postImage post
      }
    $ H.article ! A.class_ "page" $ do
      H.a ! A.href "/writing" ! A.class_ "back" $ "← Back to writing"
      H.header ! A.class_ "post-head fade" $ do
        case postSeries post of
          Just (sr, n) ->
            H.p ! A.class_ "small series-line" $
              s (seriesTitle sr ++ " · Part " ++ show n ++ " of " ++ show (length parts))
          Nothing -> mempty
        H.time ! A.class_ "small" $ s (formatDate (postDate post))
        H.h1 (s (postTitle post))
        H.div ! A.class_ "share" $ do
          H.a ! ext ("https://twitter.com/intent/tweet?url=" <> percentEncode url <> "&text=" <> percentEncode (T.pack (postTitle post))) $ "twitter"
          H.a ! ext ("https://www.linkedin.com/sharing/share-offsite/?url=" <> percentEncode url) $ "linkedin"
          H.button ! A.type_ "button" ! attr "data-copy" url $ "copy link"
      H.div ! A.class_ "prose fade d1" $ preEscapedText (T.pack body)
      case postSeries post of
        Just (sr, n) | not (null parts) -> seriesNav sr n
        _ -> mempty
  where
    url = siteUrl <> postHref (postSlug post)
    seriesTitle sid = case [T.unpack (serTitle sr) | sr <- serieses, T.unpack (serId sr) == sid] of
      (x : _) -> x
      [] -> sid
    parts = maybe [] (\(sid, _) -> seriesParts sid posts) (postSeries post)
    seriesNav sr n =
      H.nav ! attr "aria-label" (T.pack (seriesTitle sr)) ! A.class_ "series-nav" $ do
        H.p ! A.class_ "small" $ s (seriesTitle sr)
        H.ol $ mapM_ partRow parts
        H.div ! A.class_ "series-pager" $ do
          case [p | p <- parts, fmap snd (postSeries p) == Just (n - 1)] of
            (p : _) -> H.a ! A.href (v (postHref (postSlug p))) $ s ("← " ++ postTitle p)
            [] -> H.span mempty
          case [p | p <- parts, fmap snd (postSeries p) == Just (n + 1)] of
            (p : _) -> H.a ! A.href (v (postHref (postSlug p))) ! A.class_ "next" $ s (postTitle p ++ " →")
            [] -> mempty
    partRow p = H.li $ do
      H.span ! A.class_ "part-no" $ s (show (maybe 0 snd (postSeries p)) ++ ".")
      if postSlug p == postSlug post
        then H.b (s (postTitle p))
        else H.a ! A.href (v (postHref (postSlug p))) $ s (postTitle p)
