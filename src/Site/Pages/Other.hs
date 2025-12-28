-- | The other page.
module Site.Pages.Other
  ( otherPage
  ) where

import qualified Data.Text as T
import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

otherPage :: Int -> Int -> [OtherCategory] -> Html
otherPage cur total cats =
  page
    defaultPage
      { pgTitle = "Other"
      , pgDescription = "Things that have shaped who I am, music, movies, quotes and more."
      , pgPath = if cur == 1 then "/other" else "/other/page/" <> T.pack (show cur)
      }
    $ pageSection $ do
      backLink "/now" "Back to Now"
      title1 "Other"
      H.p ! A.class_ "muted fade d1" ! A.style "margin-bottom:3rem;max-width:65ch" $
        "Things that have shaped who I am, music, movies, quotes, and more. These aren't just preferences; they're pieces of culture and art that have influenced how I think, create, and see the world."
      H.div ! A.class_ "stack-16 fade d2" ! A.style "max-width:65ch" $ mapM_ cat cats
      pager "/other" cur total
  where
    cat c =
      H.div ! A.class_ "cat card-top" $ do
        H.h2 (t (ocTitle c))
        if null (ocItems c)
          then H.p ! A.class_ "empty" $ "Coming soon..."
          else H.ul $ mapM_ item (ocItems c)
    item i = H.li $ do
      H.b (t (oiName i))
      mapM_ (\d -> H.em (t ("\"" <> d <> "\""))) (oiDescription i)
