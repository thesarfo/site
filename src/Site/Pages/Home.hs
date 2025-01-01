-- | The home page.
module Site.Pages.Home
  ( home
  ) where

import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Site.Colors
import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

home :: [Entry] -> [Project] -> [Paper] -> [Quote] -> Html
home entries projects papers quotes = page defaultPage {pgNav = Nothing} $ do
  H.section ! A.class_ "hero fade" $ do
    H.p "I'm a programmer & philosopher who likes things that dont suck."
    H.p "I have a habit of making things and talking about them. This is where they accumulate."
    case quotes of
      [] -> mempty
      (q : _) ->
        H.div ! A.class_ "quote" ! attr "data-quotes" quotesJson ! A.id "quote" $ do
          H.span ! A.class_ "text" $ t ("\"" <> quoteText q <> "\"")
          H.br
          H.span ! A.class_ "by" $ t ("- " <> quoteAuthor q)

  H.section ! A.class_ "home-section fade d1" $ do
    sectionHeader "Writing" "/writing"
    dateGrid False
      [ (formatDate (entryDate e), H.a ! A.href (v (postHref (entrySlug e))) ! A.class_ "entry-link" $ s (entryTitle e))
      | e <- take 4 entries
      ]

  H.section ! A.class_ "home-section fade d2" $ do
    sectionHeader "Made" "/projects"
    H.div $ mapM_ teaser (take 3 projects)

  H.section ! A.class_ "home-section fade d3" $ do
    sectionHeader "Paper Notes" "/papers"
    dateGrid False
      [ (show (paperYear p), H.a ! A.href (v ("/papers/" <> paperSlug p)) ! A.class_ "entry-link" $ t (paperTitle p))
      | p <- take 3 papers
      ]
  where
    quotesJson =
      TE.decodeUtf8 (BL.toStrict (encode [object ["text" .= quoteText q, "author" .= quoteAuthor q] | q <- quotes]))
    teaser p =
      H.a ! ext (projHref p) ! A.class_ "teaser" $ do
        H.div ! A.class_ "teaser-top" $ do
          H.h3 (t (projName p))
          languagePill (projLanguage p)
        H.p (t (projDescription p))

languagePill :: Text -> Html
languagePill lang =
  H.span
    ! A.class_ "pill"
    ! A.style (v ("background-color:" <> languageColor lang <> "1a;color:" <> languageTextColor lang))
    $ do
      H.i ! A.style (v ("background-color:" <> languageColor lang)) $ mempty
      t lang
