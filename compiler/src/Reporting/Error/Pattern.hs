{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE OverloadedStrings #-}
module Reporting.Error.Pattern
  ( P.Error(..)
  , toReport
  )
  where

import qualified Data.List as List

import qualified Nitpick.PatternMatches as P
import qualified Reporting.Report as Report
import qualified Reporting.Render.Code as Code
import qualified Reporting.Helpers as H
import Reporting.Helpers ((<>))



-- TO REPORT


toReport :: Code.Source -> P.Error -> Report.Report
toReport source err =
  case err of
    P.Redundant caseRegion patternRegion index ->
      Report.Report "REDUNDANT PATTERN" patternRegion [] $
        Report.toCodeSnippet source caseRegion (Just patternRegion)
          (
            H.reflow $
              "The " <> H.ordinalize index <> " pattern is redundant:"
          ,
            H.reflow $
              "Any value with this shape will be handled by a previous\
              \ pattern, so it should be removed."
          )

    P.Incomplete region context unhandled ->
      case context of
        P.BadArg ->
          Report.Report "UNSAFE PATTERN" region [] $
            Report.toCodeSnippet source region Nothing
              (
                "This pattern does not cover all possiblities:"
              ,
                H.stack
                  [ "Other possibilities include:"
                  , unhandledPatternsToDocBlock unhandled
                  , H.reflow $
                      "I would have to crash if I saw one of those! So rather than\
                      \ pattern matching in function arguments, put a `case` in\
                      \ the function body to account for all possibilities."
                  ]
              )

        P.BadDestruct ->
          Report.Report "UNSAFE PATTERN" region [] $
            Report.toCodeSnippet source region Nothing
              (
                "This pattern does not cover all possible values:"
              ,
                H.stack
                  [ "Other possibilities include:"
                  , unhandledPatternsToDocBlock unhandled
                  , H.reflow $
                      "I would have to crash if I saw one of those! You can use\
                      \ `let` to deconstruct values only if there is ONE possiblity.\
                      \ Switch to a `case` expression to account for all possibilities."
                  , H.toSimpleHint $
                      "Are you calling a function that definitely returns values\
                      \ with a very specific shape? Try making the return type of\
                      \ that function more specific!"
                  ]
              )

        P.BadCase ->
          Report.Report "MISSING PATTERNS" region [] $
            Report.toCodeSnippet source region Nothing
              (
                "This `case` does not have branches for all possibilities:"
              ,
                H.stack
                  [ "Missing possibilities include:"
                  , unhandledPatternsToDocBlock unhandled
                  , H.reflow $
                      "I would have to crash if I saw one of those. Add branches for them!"
                  , H.link "Hint"
                      "If you want to write the code for each branch later, use `Debug.todo` as a placeholder. Read"
                      "missing-patterns"
                      "for more guidance on this workflow."
                  ]
              )



-- PATTERN TO DOC


unhandledPatternsToDocBlock :: [P.Pattern] -> H.Doc
unhandledPatternsToDocBlock unhandledPatterns =
  H.indent 4 $ H.dullyellow $ H.vcat $
    map (patternToDoc Unambiguous) unhandledPatterns


data Context
  = Arg
  | Head
  | Unambiguous
  deriving (Eq)


patternToDoc :: Context -> P.Pattern -> H.Doc
patternToDoc context pattern =
  case delist pattern [] of
    NonList P.Anything ->
      "_"

    NonList (P.Literal literal) ->
      case literal of
        P.Chr chr ->
          H.textToDoc ("'" <> chr <> "'")

        P.Str str ->
          H.textToDoc ("\"" <> str <> "\"")

        P.Int int ->
          H.text (show int)

    NonList (P.Ctor _ "#0" []) ->
      "()"

    NonList (P.Ctor _ "#2" [a,b]) ->
      "( " <> patternToDoc Unambiguous a <>
      ", " <> patternToDoc Unambiguous b <>
      " )"

    NonList (P.Ctor _ "#3" [a,b,c]) ->
      "( " <> patternToDoc Unambiguous a <>
      ", " <> patternToDoc Unambiguous b <>
      ", " <> patternToDoc Unambiguous c <>
      " )"

    NonList (P.Ctor _ name args) ->
      let
        ctorDoc =
          H.hsep (H.nameToDoc name : map (patternToDoc Arg) args)
      in
      if context == Arg && length args > 0 then
        "(" <> ctorDoc <> ")"
      else
        ctorDoc

    FiniteList [] ->
      "[]"

    FiniteList entries ->
      let entryDocs = map (patternToDoc Unambiguous) entries in
      "[" <> H.hcat (List.intersperse "," entryDocs) <> "]"

    Conses conses finalPattern ->
      let
        consDoc =
          foldr
            (\hd tl -> patternToDoc Head hd <> " :: " <> tl)
            (patternToDoc Unambiguous finalPattern)
            conses
      in
      if context == Unambiguous then
        consDoc
      else
        "(" <> consDoc <> ")"


data Structure
  = FiniteList [P.Pattern]
  | Conses [P.Pattern] P.Pattern
  | NonList P.Pattern


delist :: P.Pattern -> [P.Pattern] -> Structure
delist pattern revEntries =
  case pattern of
    P.Ctor _ "[]" [] ->
      FiniteList revEntries

    P.Ctor _ "::" [hd,tl] ->
      delist tl (hd:revEntries)

    _ ->
      case revEntries of
        [] ->
          NonList pattern

        _ ->
          Conses (reverse revEntries) pattern
