-- | Tag and language colours for the project pills. Ported from the old lib/language-colors.ts.
module Site.Colors
  ( languageColor
  , languageTextColor
  , tagColor
  , tagBackground
  ) where

import Data.Char (digitToInt, isHexDigit, toLower)
import Data.Text (Text)
import qualified Data.Text as T

tagColors :: [(String, String)]
tagColors =
  [ ("go", "#00ADD8")
  , ("c#", "#178600")
  , ("java", "#b07219")
  , ("python", "#3572A5")
  , ("rust", "#dea584")
  , ("postgresql", "#336791")
  , (".net", "#512BD4")
  , ("redis", "#DC382D")
  , ("fastapi", "#059669")
  , ("orm", "#0EA5E9")
  , ("audio", "#8B5CF6")
  , ("fingerprinting", "#F97316")
  , ("trading", "#10B981")
  , ("backtesting", "#7C3AED")
  , ("distributed systems", "#6366F1")
  , ("paper implementation", "#CA8A04")
  , ("library", "#EC4899")
  , ("i18n", "#14B8A6")
  , ("caching", "#F59E0B")
  ]

fallback :: String
fallback = "#64748b"

hexColor :: Text -> String
hexColor name = maybe fallback id (lookup (map toLower (T.unpack name)) tagColors)

rgb :: String -> (Int, Int, Int)
rgb ('#' : cs)
  | length cs == 6, all isHexDigit cs =
      let [a, b, c, d, e, f] = map digitToInt cs
       in (a * 16 + b, c * 16 + d, e * 16 + f)
rgb _ = (100, 116, 139)

isLight :: String -> Bool
isLight hex = (0.2126 * fromIntegral r + 0.7152 * fromIntegral g + 0.0722 * fromIntegral b) / 255 > (0.55 :: Double)
  where
    (r, g, b) = rgb hex

darken :: Double -> String -> String
darken amount hex = "rgb(" ++ show (f r) ++ ", " ++ show (f g) ++ ", " ++ show (f b) ++ ")"
  where
    (r, g, b) = rgb hex
    f v = round (fromIntegral v * (1 - amount) :: Double) :: Int

languageColor :: Text -> Text
languageColor = T.pack . hexColor

languageTextColor :: Text -> Text
languageTextColor lang
  | isLight c = T.pack (darken 0.45 c)
  | otherwise = T.pack c
  where
    c = hexColor lang

tagColor :: Text -> Text
tagColor tag
  | isLight c = T.pack (darken 0.35 c)
  | otherwise = T.pack c
  where
    c = hexColor tag

-- | The colour at 10% alpha (the old "1a" hex suffix).
tagBackground :: Text -> Text
tagBackground tag = T.pack (hexColor tag ++ "1a")
