-- | The shelf, with its search and filter.
module Site.Pages.Shelf
  ( shelfPage
  ) where

import Data.Maybe (fromMaybe, isJust)
import qualified Data.Text as T
import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

shelfPage :: ShelfFile -> Html
shelfPage sf =
  page defaultPage {pgTitle = "Shelf", pgDescription = "Papers, books, courses and tools I keep close. Mostly systems.", pgPath = "/shelf", pgNav = Just "/shelf"} $
    pageSection $ do
      H.h1 ! A.class_ "serif fade d1" ! A.style "margin:.5rem 0 1.5rem" $ "shelf"
      H.div ! A.class_ "lede fade d1" ! A.style "margin-bottom:2.5rem" $ H.p "stuff i've saved over time. papers, books, talks, mostly systems."
      H.div ! A.class_ "shelf-tools fade d2" $ do
        H.input ! A.type_ "search" ! A.id "shelf-search" ! A.class_ "shelf-search" ! A.placeholder "search" ! attr "aria-label" "search the shelf"
        H.div ! A.class_ "kinds" ! A.id "shelf-kinds" ! A.role "group" ! attr "aria-label" "filter by type" $
          mapM_ (\k -> H.button ! A.type_ "button" ! attr "data-kind" k ! attr "aria-pressed" (if k == "all" then "true" else "false") $ t k) (sfKinds sf)
        H.p ! A.class_ "match-count" ! A.id "shelf-count" ! A.hidden "" $ mempty
      H.div ! A.class_ "shelves fade d2" ! A.id "shelves" $ mapM_ shelf (zip [1 :: Int ..] (sfShelves sf))
      H.p ! A.class_ "empty" ! A.id "shelf-empty" ! A.hidden "" $ "nothing on this shelf matches."
  where
    pad2 n = let x = show n in if length x < 2 then '0' : x else x
    shelf (si, sh) =
      H.section ! A.id (v (shelfId sh)) ! A.class_ "shelf" $ do
        H.div ! A.class_ "shelf-head" $ do
          H.span (s (pad2 si))
          H.h2 (t (shelfName sh))
          H.span ! A.class_ "count" ! attr "data-total" (T.pack (show (length (shelfItems sh)))) $ s (show (length (shelfItems sh)) ++ " items")
        H.ul $ mapM_ (item sh si) (zip [1 :: Int ..] (shelfItems sh))
    item sh si (ii, it) =
      H.li
        ! A.class_ "shelf-item"
        ! attr "data-kind" (itemKind it)
        ! attr "data-text" (T.toLower (T.unwords [itemTitle it, fromMaybe "" (itemBy it), itemNote it]))
        $ do
          H.span ! A.class_ "no" $ s (pad2 si ++ "." ++ pad2 ii)
          H.div $ do
            let ttl = H.span ! A.class_ "ttl" $ do
                  t (itemTitle it)
                  if isJust (itemUrl it) then H.span ! A.class_ "arrow" ! attr "aria-hidden" "true" $ " ↗" else mempty
            case itemUrl it of
              Just u -> H.a ! ext u $ ttl
              Nothing -> ttl
            H.div ! A.class_ "meta" $ do
              H.span ! A.class_ "shelf-name" $ t (shelfName sh)
              t (T.intercalate " · " (itemKind it : maybe [] pure (itemYear it)))
            H.p (t (maybe "" (<> ". ") (itemBy it) <> itemNote it))
