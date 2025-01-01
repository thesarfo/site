-- | The 404 page.
module Site.Pages.NotFound
  ( notFoundPage
  ) where

import Site.Pages.Common
import Site.Html
import Site.Types
import Text.Blaze.Html5 (Html, (!))
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A
import Text.Blaze.Internal (preEscapedText)

notFoundPage :: Html
notFoundPage =
  page defaultPage {pgTitle = "Not found", pgDescription = "This page doesn't exist.", pgPath = "/404"} $
    H.section ! A.class_ "lost fade" $ do
      H.div $ do
        H.p ! A.class_ "code" $ "Error 404"
        H.h1 "Nobody's home."
        H.p $ do
          "This ghost has been looking for "
          H.code ! A.id "lost-path" ! A.style "color:hsl(var(--foreground));word-break:break-all" $ "that page"
          " all day. It might have moved, or the link might be wrong."
        H.p "Here are some places that do exist."
        H.ul $ mapM_ (\(to, label) -> H.li (H.a ! A.href to ! A.class_ "ulink" $ label)) [("/", "Home"), ("/writing", "Writing"), ("/projects", "Projects"), ("/now", "Now")]
      ghost

ghost :: Html
ghost =
  preEscapedText $
    "<svg class=\"ghost\" viewBox=\"0 0 260 240\" role=\"img\" aria-label=\"A confused ghost searching with a magnifying glass\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"3\" stroke-linecap=\"round\" stroke-linejoin=\"round\">"
      <> "<ellipse cx=\"130\" cy=\"218\" rx=\"46\" ry=\"7\" stroke-width=\"2\" opacity=\".35\"/>"
      <> "<path d=\"M78 190 V105 C78 68 100 48 130 48 C160 48 182 68 182 105 V190 L166 176 L148 192 L130 176 L112 192 L94 176 Z\"/>"
      <> "<circle cx=\"112\" cy=\"104\" r=\"11\"/><circle cx=\"108\" cy=\"106\" r=\"4\" fill=\"currentColor\" stroke=\"none\"/>"
      <> "<circle cx=\"150\" cy=\"102\" r=\"7\"/><circle cx=\"147\" cy=\"104\" r=\"3\" fill=\"currentColor\" stroke=\"none\"/>"
      <> "<path d=\"M116 138 q7 -6 14 0 t14 0\"/><path d=\"M78 130 q-16 6 -20 20\"/>"
      <> "<path d=\"M182 128 L206 100\"/><circle cx=\"222\" cy=\"82\" r=\"20\"/><path d=\"M212 76 q4 -8 12 -8\" stroke-width=\"2\" opacity=\".6\"/>"
      <> "<text x=\"40\" y=\"70\" font-size=\"30\" fill=\"currentColor\" stroke=\"none\">?</text>"
      <> "<text x=\"62\" y=\"38\" font-size=\"20\" fill=\"currentColor\" stroke=\"none\">?</text>"
      <> "<text x=\"20\" y=\"116\" font-size=\"22\" fill=\"currentColor\" stroke=\"none\">?</text>"
      <> "</svg>"
