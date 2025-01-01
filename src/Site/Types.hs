{-# LANGUAGE DeriveGeneric #-}

-- | Records for the JSON files under site/data, plus the post type built from
-- markdown front matter.
module Site.Types
  ( Link (..)
  , Shot (..)
  , Project (..)
  , Paper (..)
  , ShelfItem (..)
  , Shelf (..)
  , ShelfFile (..)
  , Quote (..)
  , Render (..)
  , OtherItem (..)
  , OtherCategory (..)
  , Chapter (..)
  , Book (..)
  , Series (..)
  , Post (..)
  , Entry (..)
  , writingEntries
  , newestFirst
  , seriesParts
  ) where

import Data.Aeson hiding (Series)
import Data.Char (toLower)
import Data.List (sortOn)
import Data.Ord (Down (..))
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | Drop an n-letter field prefix and lower-case what is left: `projHref` -> "href".
opts :: Int -> Options
opts n = defaultOptions {fieldLabelModifier = lower1 . drop n, omitNothingFields = True}
  where
    lower1 (c : cs) = toLower c : cs
    lower1 [] = []

data Link = Link {linkLabel :: Text, linkHref :: Text}
  deriving (Show, Generic)

instance FromJSON Link where parseJSON = genericParseJSON (opts 4)

data Shot = Shot
  { shotSrc :: Text
  , shotThumb :: Text
  , shotWidth :: Int
  , shotHeight :: Int
  , shotCaption :: Text
  }
  deriving (Show, Generic)

instance FromJSON Shot where parseJSON = genericParseJSON (opts 4)

data Project = Project
  { projName :: Text
  , projYear :: Text
  , projDescription :: Text
  , projWriteup :: [Text]
  , projTags :: [Text]
  , projLanguage :: Text
  , projHref :: Text
  , projLinks :: Maybe [Link]
  , projStatus :: Maybe Text
  , projShots :: Maybe [Shot]
  }
  deriving (Show, Generic)

instance FromJSON Project where parseJSON = genericParseJSON (opts 4)

data Paper = Paper
  { paperSlug :: Text
  , paperTitle :: Text
  , paperAuthors :: Text
  , paperYear :: Int
  , paperSummary :: Text
  , paperInteresting :: Text
  , paperLink :: Maybe Text
  }
  deriving (Show, Generic)

instance FromJSON Paper where parseJSON = genericParseJSON (opts 5)

data ShelfItem = ShelfItem
  { itemTitle :: Text
  , itemUrl :: Maybe Text
  , itemKind :: Text
  , itemYear :: Maybe Text
  , itemBy :: Maybe Text
  , itemNote :: Text
  }
  deriving (Show, Generic)

instance FromJSON ShelfItem where parseJSON = genericParseJSON (opts 4)

data Shelf = Shelf {shelfId :: Text, shelfName :: Text, shelfItems :: [ShelfItem]}
  deriving (Show, Generic)

instance FromJSON Shelf where parseJSON = genericParseJSON (opts 5)

data ShelfFile = ShelfFile {sfKinds :: [Text], sfShelves :: [Shelf]}
  deriving (Show, Generic)

instance FromJSON ShelfFile where parseJSON = genericParseJSON (opts 2)

data Quote = Quote {quoteText :: Text, quoteAuthor :: Text}
  deriving (Show, Generic)

instance FromJSON Quote where parseJSON = genericParseJSON (opts 5)

data Render = Render
  { renderFile :: Text
  , renderTitle :: Text
  , renderWidth :: Int
  , renderHeight :: Int
  }
  deriving (Show, Generic)

instance FromJSON Render where parseJSON = genericParseJSON (opts 6)

data OtherItem = OtherItem {oiName :: Text, oiDescription :: Maybe Text}
  deriving (Show, Generic)

instance FromJSON OtherItem where parseJSON = genericParseJSON (opts 2)

data OtherCategory = OtherCategory {ocTitle :: Text, ocItems :: [OtherItem]}
  deriving (Show, Generic)

instance FromJSON OtherCategory where parseJSON = genericParseJSON (opts 2)

data Chapter = Chapter {chNumber :: Int, chTitle :: Text}
  deriving (Show, Generic)

instance FromJSON Chapter where parseJSON = genericParseJSON (opts 2)

data Book = Book
  { bookSlug :: Text
  , bookTitle :: Text
  , bookAuthor :: Text
  , bookYear :: Int
  , bookChapters :: [Chapter]
  }
  deriving (Show, Generic)

instance FromJSON Book where parseJSON = genericParseJSON (opts 4)

data Series = Series {serId :: Text, serTitle :: Text, serDescription :: Text}
  deriving (Show, Generic)

instance FromJSON Series where parseJSON = genericParseJSON (opts 3)

-- | What a post's front matter says. The body is rendered separately.
data Post = Post
  { postSlug :: String
  , postTitle :: String
  , postDate :: String -- ^ ISO yyyy-mm-dd
  , postExcerpt :: String
  , postImage :: Maybe String
  , postSeries :: Maybe (String, Int) -- ^ series id and part number
  }
  deriving (Show)

-- | A row in a writing list. A series shows up once, under its own title.
data Entry = Entry {entryTitle :: String, entryDate :: String, entrySlug :: String}

-- | Posts newest first; within one day the later part of a series comes first.
newestFirst :: [Post] -> [Post]
newestFirst = sortOn (\p -> (Down (postDate p), Down (maybe 0 snd (postSeries p)), postSlug p))

seriesParts :: String -> [Post] -> [Post]
seriesParts sid posts =
  sortOn (maybe 0 snd . postSeries) [p | p <- posts, fmap fst (postSeries p) == Just sid]

writingEntries :: [Series] -> [Post] -> [Entry]
writingEntries serieses posts = go Set.empty (newestFirst posts)
  where
    go _ [] = []
    go seen (p : ps) = case postSeries p of
      Nothing -> Entry (postTitle p) (postDate p) (postSlug p) : go seen ps
      Just (sid, _)
        | sid `Set.member` seen -> go seen ps
        | otherwise ->
            let title = case [T.unpack (serTitle s) | s <- serieses, T.unpack (serId s) == sid] of
                  (t : _) -> t
                  [] -> sid
                firstPart = case seriesParts sid posts of
                  (x : _) -> postSlug x
                  [] -> postSlug p
             in Entry title (postDate p) firstPart : go (Set.insert sid seen) ps
