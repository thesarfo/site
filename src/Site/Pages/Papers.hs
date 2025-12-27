-- | Paper notes: the paginated list and a single paper.
module Site.Pages.Papers
  ( papersPage
  , paperPage
  ) where

import qualified Data.Text as T
import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

papersPage :: Int -> Int -> [Paper] -> Html
papersPage cur total papers =
  page
    defaultPage
      { pgTitle = "Papers"
      , pgDescription = "I read research papers to understand why systems work the way they do, not just how to use them. These are short, opinionated summaries written mostly for my future self."
      , pgPath = if cur == 1 then "/papers" else "/papers/page/" <> T.pack (show cur)
      }
    $ pageSection $ do
      title1 "Papers"
      ledeP "Short, opinionated summaries written mostly for my future self."
      H.div ! A.class_ "stack-16 fade d2" $ mapM_ card papers
      pager "/papers" cur total
  where
    card p =
      H.article ! A.class_ "paper card-top" $ do
        H.div ! A.class_ "byline" $ t (paperAuthors p <> " · " <> T.pack (show (paperYear p)))
        H.h2 $ H.a ! A.href (v ("/papers/" <> paperSlug p)) $ t (paperTitle p)
        H.div ! A.class_ "paper-body" $ do
          H.p (t (paperSummary p))
          H.div $ do
            H.h3 "What I found interesting"
            H.p (t (paperInteresting p))
        mapM_ (\l -> H.a ! ext l ! A.class_ "read-paper" $ "Read paper ↗") (paperLink p)

paperPage :: Paper -> Html
paperPage p =
  page
    defaultPage
      { pgTitle = paperTitle p
      , pgDescription = if T.null (paperSummary p) then "Notes on " <> paperTitle p <> " (" <> paperAuthors p <> ", " <> T.pack (show (paperYear p)) <> ")." else paperSummary p
      , pgPath = "/papers/" <> paperSlug p
      }
    $ H.section ! A.class_ "page paper-detail" $ do
      H.header ! A.class_ "fade" $ do
        H.div ! A.class_ "byline" ! A.style "margin-bottom:.75rem" $ t (paperAuthors p <> " · " <> T.pack (show (paperYear p)))
        H.h1 ! A.class_ "page-title" $ t (paperTitle p)
      H.div ! A.class_ "body fade d1" $ do
        if T.null (paperSummary p) then mempty else H.p (t (paperSummary p))
        H.div $ do
          H.h2 "What I found interesting"
          H.p (t (paperInteresting p))
        mapM_ (\l -> H.a ! ext l $ "Read the original paper ↗") (paperLink p)
      H.nav ! A.class_ "foot-nav fade d2" $ H.a ! A.href "/papers" $ "← All paper notes"
