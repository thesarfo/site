-- | Book notes: the list, a book and a chapter.
module Site.Pages.Books
  ( booksIndex
  , bookPage
  , chapterPage
  ) where

import qualified Data.Text as T
import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A
import Text.Blaze.Internal (preEscapedText)

booksIndex :: [Book] -> Html
booksIndex books =
  page defaultPage {pgTitle = "Books", pgDescription = "Notes on books I've read, chapter by chapter.", pgPath = "/books"} $
    pageSection $ do
      title1 "Books"
      ledeP "Notes on books I've read, chapter by chapter."
      H.div ! A.class_ "fade d2" $ mapM_ row books
  where
    row b =
      H.a ! A.href (v ("/books/" <> bookSlug b)) ! A.class_ "book-row" $ do
        H.h2 (t (bookTitle b))
        H.p (t (bookAuthor b <> " · " <> T.pack (show (bookYear b)) <> " · " <> T.pack (show (length (bookChapters b))) <> " chapters"))

bookPage :: Book -> Html
bookPage b =
  page defaultPage {pgTitle = bookTitle b, pgDescription = "Chapter notes for " <> bookTitle b <> " by " <> bookAuthor b <> ".", pgPath = "/books/" <> bookSlug b} $
    pageSection $ do
      backLink "/books" "Back to books"
      H.header ! A.class_ "fade" ! A.style "margin-bottom:3rem" $ do
        H.h1 ! A.class_ "page-title tight" $ t (bookTitle b)
        H.p ! A.class_ "muted" ! A.style "font-size:.875rem" $ t (bookAuthor b <> " · " <> T.pack (show (bookYear b)))
      H.div ! A.class_ "fade d1" $ mapM_ row (bookChapters b)
  where
    row c =
      H.a ! A.href (v ("/books/" <> bookSlug b <> "/" <> T.pack (show (chNumber c)))) ! A.class_ "chapter-row" $ do
        H.span ! A.class_ "n" $ s (show (chNumber c))
        H.span ! A.class_ "t" $ t (chTitle c)

chapterPage :: Book -> Chapter -> String -> Html
chapterPage b c body =
  page
    defaultPage
      { pgTitle = "Ch. " <> T.pack (show (chNumber c)) <> ", " <> chTitle c
      , pgDescription = bookTitle b <> " · Chapter " <> T.pack (show (chNumber c)) <> ": " <> chTitle c
      , pgPath = chapterPath c
      }
    $ H.article ! A.class_ "page" $ do
      H.a ! A.href (v ("/books/" <> bookSlug b)) ! A.class_ "back" ! A.style "margin-bottom:2.5rem" $ t ("← " <> bookTitle b)
      H.header ! A.class_ "fade" ! A.style "margin-bottom:3rem" $ do
        H.p ! A.class_ "eyebrow" $ s ("Chapter " ++ show (chNumber c))
        H.h1 ! A.class_ "page-title" ! A.style "margin-bottom:0" $ t (chTitle c)
      H.div ! A.class_ "prose notes fade d1" $ preEscapedText (T.pack body)
      H.nav ! A.class_ "chapter-nav fade d2" $ do
        case neighbour (-1) of
          Just p -> H.a ! A.href (v (chapterPath p)) $ t ("← Ch. " <> T.pack (show (chNumber p)) <> " · " <> chTitle p)
          Nothing -> H.span mempty
        mapM_ (\n -> H.a ! A.href (v (chapterPath n)) $ t ("Ch. " <> T.pack (show (chNumber n)) <> " · " <> chTitle n <> " →")) (neighbour 1)
  where
    chapterPath ch = "/books/" <> bookSlug b <> "/" <> T.pack (show (chNumber ch))
    neighbour d = case [x | x <- bookChapters b, chNumber x == chNumber c + d] of
      (x : _) -> Just x
      [] -> Nothing
