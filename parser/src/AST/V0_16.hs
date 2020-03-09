{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}

module AST.V0_16 where

import Data.Bifunctor
import Data.Coapplicative
import Data.Int (Int64)
import qualified Data.Indexed as I
import qualified Cheapskate.Types as Markdown


type List a = [a]


newtype ForceMultiline =
    ForceMultiline Bool
    deriving (Eq, Show)


data LowercaseIdentifier =
    LowercaseIdentifier String
    deriving (Eq, Ord, Show)


data UppercaseIdentifier =
    UppercaseIdentifier String
    deriving (Eq, Ord, Show)


data SymbolIdentifier =
    SymbolIdentifier String
    deriving (Eq, Ord, Show)


data Comment
    = BlockComment (List String)
    | LineComment String
    | CommentTrickOpener
    | CommentTrickCloser
    | CommentTrickBlock String
    deriving (Eq, Ord, Show)
type Comments = List Comment


data Commented c a =
    C c a
    deriving (Eq, Ord, Functor, Show) -- TODO: is Ord needed?

instance Coapplicative (Commented c) where
    extract (C _ a) = a
    {-# INLINE extract #-}

type C1 l1 a = Commented Comments a
type C2 l1 l2 a = Commented (Comments, Comments) a
type C3 l1 l2 l3 a = Commented (Comments, Comments, Comments) a

type C0Eol a = Commented (Maybe String) a
type C1Eol l1 a = Commented (Comments, Maybe String) a
type C2Eol l1 l2 a = Commented (Comments, Comments, Maybe String) a


{-| This represents a list of things separated by comments.

Currently, the first item will never have leading comments.
However, if Elm ever changes to allow optional leading delimiters, then
comments before the first delimiter will go there.
-}
data BeforeSeparator; data AfterSeparator
newtype Sequence a =
    Sequence (List (C2Eol BeforeSeparator AfterSeparator a))
    deriving (Eq, Functor, Show)

instance Foldable Sequence where
    foldMap f (Sequence items) = foldMap (f . extract) items

sequenceToList :: Sequence a -> List (C2Eol BeforeSeparator AfterSeparator a)
sequenceToList (Sequence items) = items


{-| This represents a list of things between clear start and end delimiters.
Comments can appear before and after any item, or alone if there are no items.

For example:
  ( {- nothing -} )
  ( a, b )

TODO: this should be replaced with (Sequence a, Comments)
-}
data Inside
data ContainedCommentedList a
    = Empty (C1 Inside ())
    | Items [C2 Before After a]


{-| This represents a list of things that have no clear start and end
delimiters.

If there is more than one item in the list, then comments can appear.
Comments can appear after the first item, before the last item, and
around any other item.
An end-of-line comment can appear after the last item.

If there is only one item in the list, an end-of-line comment can appear after the item.

TODO: this should be replaced with (Sequence a)
-}
data AfterFirstTerm; data BeforeLastTerm; data BeforeTerm; data AfterTerm
data ExposedCommentedList a
    = Single (C0Eol a)
    | Multiple (C1Eol AfterFirstTerm a) [C2Eol BeforeTerm AfterTerm a] (C1Eol BeforeLastTerm a)


{-| This represents a list of things that have a clear start delimiter but no
clear end delimiter.
There must be at least one item.
Comments can appear before the last item, or around any other item.
An end-of-line comment can also appear after the last item.

For example:
  = a
  = a, b, c

TODO: this should be replaced with (Sequence a)
-}
data OpenCommentedList a
    = OpenCommentedList [C2Eol BeforeTerm AfterTerm a] (C1Eol BeforeLastTerm a)
    deriving (Eq, Show, Functor)

instance Foldable OpenCommentedList where
    foldMap f (OpenCommentedList rest last) = foldMap (f . extract) rest <> (f . extract) last


exposedToOpen :: Comments -> ExposedCommentedList a -> OpenCommentedList a
exposedToOpen pre exposed =
    case exposed of
        Single (C eol item) ->
            OpenCommentedList [] (C (pre, eol) item)

        Multiple (C (postFirst, eol) first') rest' lst ->
            OpenCommentedList (C (pre, postFirst, eol) first' : rest') lst


{-| Represents a delimiter-separated pair.

Comments can appear after the key or before the value.

For example:

  key = value
  key : value
-}
data AfterKey; data BeforeValue
data Pair key value =
    Pair
        { _key :: C1 AfterKey key
        , _value :: C1 BeforeValue value
        , forceMultiline :: ForceMultiline
        }
    deriving (Show, Eq, Functor)


data Multiline
    = JoinAll
    | SplitAll
    deriving (Eq, Show)


isMultiline :: Multiline -> Bool
isMultiline JoinAll = False
isMultiline SplitAll = True


data FunctionApplicationMultiline
    = FASplitFirst
    | FAJoinFirst Multiline
    deriving (Eq, Show)


data Assoc = L | N | R
    deriving (Eq, Show)

assocToString :: Assoc -> String
assocToString assoc =
    case assoc of
      L -> "left"
      N -> "non"
      R -> "right"


data NameWithArgs name arg =
    NameWithArgs name [C1 BeforeTerm arg]
    deriving (Eq, Show, Functor)
instance Foldable (NameWithArgs name) where
    foldMap f (NameWithArgs _ args) = foldMap (f . extract) args


data IntRepresentation
  = DecimalInt
  | HexadecimalInt
  deriving (Eq, Show)


data FloatRepresentation
  = DecimalFloat
  | ExponentFloat
  deriving (Eq, Show)


data LiteralValue
    = IntNum Int64 IntRepresentation
    | FloatNum Double FloatRepresentation
    | Chr Char
    | Str String Bool
    | Boolean Bool
    deriving (Eq, Show)


data Ref ns
    = VarRef ns LowercaseIdentifier
    | TagRef ns UppercaseIdentifier
    | OpRef SymbolIdentifier
    deriving (Eq, Ord, Show, Functor)


data TypeConstructor ctorRef
    = NamedConstructor ctorRef
    | TupleConstructor Int -- will be 2 or greater, indicating the number of elements in the tuple
    deriving (Eq, Show, Functor)


data UnaryOperator =
    Negative
    deriving (Eq, Show)


data BinopsClause varRef expr =
    BinopsClause Comments varRef Comments expr
    deriving (Eq, Show, Functor)

instance Bifunctor BinopsClause where
    bimap fvr fe = \case
        BinopsClause c1 vr c2 e -> BinopsClause c1 (fvr vr) c2 (fe e)


data BeforePredicate; data AfterPredicate; data BeforeBody; data AfterBody
data IfClause e =
    IfClause (C2 BeforePredicate AfterPredicate e) (C2 BeforeBody AfterBody e)
    deriving (Eq, Show, Functor)


-- TODO: merge this into AST
data TopLevelStructure a
    = DocComment Markdown.Blocks
    | BodyComment Comment
    | Entry a
    deriving (Eq, Show, Functor)


data NodeKind
    = ModuleNK
    | DeclarationNK
    | ExpressionNK
    | LetDeclarationNK
    | CaseBranchNK
    | PatternNK
    | TypeNK


-- TODO: convert comment types to DataKinds
data Before; data After
data BeforePattern; data BeforeArrow; data AfterArrow
data AfterName; data BeforeType; data AfterEquals

data AST typeRef ctorRef varRef (getType :: NodeKind -> *) (kind :: NodeKind) where
    --
    -- Declarations
    --

    Definition ::
        getType 'PatternNK
        -> [C1 BeforeTerm (getType 'PatternNK)]
        -> Comments
        -> getType 'ExpressionNK
        -> AST typeRef ctorRef varRef getType 'DeclarationNK
    TypeAnnotation ::
        C1 AfterName (Ref ())
        -> C1 BeforeType (getType 'TypeNK)
        -> AST typeRef ctorRef varRef getType 'DeclarationNK
    Datatype ::
        { nameWithArgs :: C2 Before After (NameWithArgs UppercaseIdentifier LowercaseIdentifier)
        , tags :: OpenCommentedList (NameWithArgs UppercaseIdentifier (getType 'TypeNK))
        }
        -> AST typeRef ctorRef varRef getType 'DeclarationNK
    TypeAlias ::
        Comments
        -> C2 Before After (NameWithArgs UppercaseIdentifier LowercaseIdentifier)
        -> C1 AfterEquals (getType 'TypeNK)
        -> AST typeRef ctorRef varRef getType 'DeclarationNK
    PortAnnotation ::
        C2 Before After LowercaseIdentifier
        -> Comments
        -> getType 'TypeNK
        -> AST typeRef ctorRef varRef getType 'DeclarationNK
    PortDefinition ::
        C2 Before After LowercaseIdentifier
        -> Comments
        -> getType 'ExpressionNK
        -> AST typeRef ctorRef varRef getType 'DeclarationNK
    Fixity ::
        Assoc
        -> Comments
        -> Int
        -> Comments
        -> varRef
        -> AST typeRef ctorRef varRef getType 'DeclarationNK
    Fixity_0_19 ::
        C1 Before Assoc
        -> C1 Before Int
        -> C2 Before After SymbolIdentifier
        -> C1 Before LowercaseIdentifier
        -> AST typeRef ctorRef varRef getType 'DeclarationNK

    --
    -- Expressions
    --

    Unit ::
        Comments
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    Literal ::
        LiteralValue
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    VarExpr ::
        varRef
        -> AST typeRef ctorRef varRef getType 'ExpressionNK

    App ::
        getType 'ExpressionNK
        -> [C1 Before (getType 'ExpressionNK)]
        -> FunctionApplicationMultiline
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    Unary ::
        UnaryOperator
        -> getType 'ExpressionNK
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    Binops ::
        getType 'ExpressionNK
        -> [BinopsClause varRef (getType 'ExpressionNK)]
        -> Bool
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    Parens ::
        C2 Before After (getType 'ExpressionNK)
        -> AST typeRef ctorRef varRef getType 'ExpressionNK

    ExplicitList ::
        { terms :: Sequence (getType 'ExpressionNK)
        , trailingComments_el :: Comments
        , forceMultiline_el :: ForceMultiline
        }
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    Range ::
        C2 Before After (getType 'ExpressionNK)
        -> C2 Before After (getType 'ExpressionNK)
        -> Bool
        -> AST typeRef ctorRef varRef getType 'ExpressionNK

    Tuple ::
        [C2 Before After (getType 'ExpressionNK)]
        -> Bool
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    TupleFunction ::
        Int -- will be 2 or greater, indicating the number of elements in the tuple
        -> AST typeRef ctorRef varRef getType 'ExpressionNK

    Record ::
        { base_r :: Maybe (C2 Before After LowercaseIdentifier)
        , fields_r :: Sequence (Pair LowercaseIdentifier (getType 'ExpressionNK))
        , trailingComments_r :: Comments
        , forceMultiline_r :: ForceMultiline
        }
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    Access ::
        getType 'ExpressionNK
        -> LowercaseIdentifier
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    AccessFunction ::
        LowercaseIdentifier
        -> AST typeRef ctorRef varRef getType 'ExpressionNK

    Lambda ::
        [C1 Before (getType 'PatternNK)]
        -> Comments
        -> getType 'ExpressionNK
        -> Bool
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    If ::
        IfClause (getType 'ExpressionNK)
        -> [C1 Before (IfClause (getType 'ExpressionNK))]
        -> C1 Before (getType 'ExpressionNK)
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    Let ::
        [getType 'LetDeclarationNK]
        -> Comments
        -> getType 'ExpressionNK
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    LetDefinition ::
        getType 'PatternNK
        -> [C1 Before (getType 'PatternNK)]
        -> Comments
        -> getType 'ExpressionNK
        -> AST typeRef ctorRef varRef getType 'LetDeclarationNK
    LetAnnotation ::
        C1 After (Ref ())
        -> C1 Before (getType 'TypeNK)
        -> AST typeRef ctorRef varRef getType 'LetDeclarationNK
    LetComment ::
        Comment
        -> AST typeRef ctorRef varRef getType 'LetDeclarationNK
    Case ::
        (C2 Before After (getType 'ExpressionNK), Bool)
        -> [getType 'CaseBranchNK]
        -> AST typeRef ctorRef varRef getType 'ExpressionNK
    CaseBranch ::
        { beforePattern :: Comments
        , beforeArrow :: Comments
        , afterArrow :: Comments
        , pattern :: getType 'PatternNK
        , body :: getType 'ExpressionNK
        }
        -> AST typeRef ctorRef varRef getType 'CaseBranchNK

    -- for type checking and code gen only
    GLShader ::
        String
        -> AST typeRef ctorRef varRef getType 'ExpressionNK


    --
    -- Patterns
    --

    Anything ::
        AST typeRef ctorRef varRef getType 'PatternNK
    UnitPattern ::
        Comments
        -> AST typeRef ctorRef varRef getType 'PatternNK
    LiteralPattern ::
        LiteralValue
        -> AST typeRef ctorRef varRef getType 'PatternNK
    VarPattern ::
        LowercaseIdentifier
        -> AST typeRef ctorRef varRef getType 'PatternNK
    OpPattern ::
        SymbolIdentifier
        -> AST typeRef ctorRef varRef getType 'PatternNK
    DataPattern ::
        typeRef
        -> [C1 BeforeTerm (getType 'PatternNK)]
        -> AST typeRef ctorRef varRef getType 'PatternNK
    PatternParens ::
        C2 Before After (getType 'PatternNK)
        -> AST typeRef ctorRef varRef getType 'PatternNK
    TuplePattern ::
        [C2 BeforeTerm AfterTerm (getType 'PatternNK)]
        -> AST typeRef ctorRef varRef getType 'PatternNK
    EmptyListPattern ::
        Comments
        -> AST typeRef ctorRef varRef getType 'PatternNK
    ListPattern ::
        [C2 BeforeTerm AfterTerm (getType 'PatternNK)]
        -> AST typeRef ctorRef varRef getType 'PatternNK
    ConsPattern ::
        { first_cp :: C0Eol (getType 'PatternNK)
        , rest_cp :: Sequence (getType 'PatternNK)
        }
        -> AST typeRef ctorRef varRef getType 'PatternNK
    EmptyRecordPattern ::
        Comments
        -> AST typeRef ctorRef varRef getType 'PatternNK
    RecordPattern ::
        [C2 BeforeTerm AfterTerm LowercaseIdentifier]
        -> AST typeRef ctorRef varRef getType 'PatternNK
    Alias ::
        C1 After (getType 'PatternNK)
        -> C1 Before LowercaseIdentifier
        -> AST typeRef ctorRef varRef getType 'PatternNK


    --
    -- Types
    --

    UnitType ::
        Comments
        -> AST typeRef ctorRef varRef getType 'TypeNK
    TypeVariable ::
        LowercaseIdentifier
        -> AST typeRef ctorRef varRef getType 'TypeNK
    TypeConstruction ::
        TypeConstructor ctorRef
        -> [C1 Before (getType 'TypeNK)]
        -> AST typeRef ctorRef varRef getType 'TypeNK
    TypeParens ::
        C2 Before After (getType 'TypeNK)
        -> AST typeRef ctorRef varRef getType 'TypeNK
    TupleType ::
        [C2Eol Before After (getType 'TypeNK)]
        -> AST typeRef ctorRef varRef getType 'TypeNK
    RecordType ::
        { base_rt :: Maybe (C2 Before After LowercaseIdentifier)
        , fields_rt :: Sequence (Pair LowercaseIdentifier (getType 'TypeNK))
        , trailingComments_rt :: Comments
        , forceMultiline_rt :: ForceMultiline
        }
        -> AST typeRef ctorRef varRef getType 'TypeNK
    FunctionType ::
        { first_ft :: C0Eol (getType 'TypeNK)
        , rest_ft :: Sequence (getType 'TypeNK)
        , forceMultiline_ft :: ForceMultiline
        }
        -> AST typeRef ctorRef varRef getType 'TypeNK

deriving instance
    ( Eq typeRef, Eq ctorRef, Eq varRef
    , Eq (getType 'ExpressionNK)
    , Eq (getType 'LetDeclarationNK)
    , Eq (getType 'CaseBranchNK)
    , Eq (getType 'PatternNK)
    , Eq (getType 'TypeNK)
    ) =>
    Eq (AST typeRef ctorRef varRef getType kind)
deriving instance
    ( Show typeRef, Show ctorRef, Show varRef
    , Show (getType 'ExpressionNK)
    , Show (getType 'LetDeclarationNK)
    , Show (getType 'CaseBranchNK)
    , Show (getType 'PatternNK)
    , Show (getType 'TypeNK)
    ) =>
    Show (AST typeRef ctorRef varRef getType kind)


mapAll ::
    (typeRef1 -> typeRef2) -> (ctorRef1 -> ctorRef2) -> (varRef1 -> varRef2)
    -> (forall kind. getType1 kind -> getType2 kind)
    -> (forall kind.
        AST typeRef1 ctorRef1 varRef1 getType1 kind
        -> AST typeRef2 ctorRef2 varRef2 getType2 kind
        )
mapAll ftyp fctor fvar fast = \case
    -- Declaration
    Definition name args c e -> Definition (fast name) (fmap (fmap fast) args) c (fast e)
    TypeAnnotation name t -> TypeAnnotation name (fmap fast t)
    Datatype nameWithArgs ctors -> Datatype nameWithArgs (fmap (fmap fast) ctors)
    TypeAlias c nameWithArgs t -> TypeAlias c nameWithArgs (fmap fast t)
    PortAnnotation name c t -> PortAnnotation name c (fast t)
    PortDefinition name c e -> PortDefinition name c (fast e)
    Fixity a c n c' name -> Fixity a c n c' (fvar name)
    Fixity_0_19 a n op name -> Fixity_0_19 a n op name

    -- Expressions
    Unit c -> Unit c
    Literal l -> Literal l
    VarExpr var -> VarExpr (fvar var)
    App first rest ml -> App (fast first) (fmap (fmap fast) rest) ml
    Unary op e -> Unary op (fast e)
    Binops first ops ml -> Binops (fast first) (fmap (bimap fvar fast) ops) ml
    Parens e -> Parens (fmap fast e)
    ExplicitList terms c ml -> ExplicitList (fmap fast terms) c ml
    Range left right ml -> Range (fmap fast left) (fmap fast right) ml
    Tuple terms ml -> Tuple (fmap (fmap fast) terms) ml
    TupleFunction n -> TupleFunction n
    Record base fields c ml -> Record base (fmap (fmap fast) fields) c ml
    Access e field -> Access (fast e) field
    AccessFunction field -> AccessFunction field
    Lambda args c e ml -> Lambda (fmap (fmap fast) args) c (fast e) ml
    If cond elsifs els -> If (fmap fast cond) (fmap (fmap $ fmap fast) elsifs) (fmap fast els)
    Let decls c e -> Let (fmap fast decls) c (fast e)
    LetDefinition first rest c e -> LetDefinition (fast first) (fmap (fmap fast) rest) c (fast e)
    LetAnnotation name typ -> LetAnnotation name (fmap fast typ)
    LetComment c -> LetComment c
    Case (cond, ml) branches -> Case (fmap fast cond, ml) (fmap fast branches)
    CaseBranch c1 c2 c3 p e -> CaseBranch c1 c2 c3 (fast p) (fast e)
    GLShader s -> GLShader s

    -- Patterns
    Anything -> Anything
    UnitPattern c -> UnitPattern c
    LiteralPattern l -> LiteralPattern l
    VarPattern l -> VarPattern l
    OpPattern s -> OpPattern s
    DataPattern typ pats -> DataPattern (ftyp typ) (fmap (fmap fast) pats)
    PatternParens pat -> PatternParens (fmap fast pat)
    TuplePattern pats -> TuplePattern (fmap (fmap fast) pats)
    EmptyListPattern c -> EmptyListPattern c
    ListPattern pats -> ListPattern (fmap (fmap fast) pats)
    ConsPattern first rest -> ConsPattern (fmap fast first) (fmap fast rest)
    EmptyRecordPattern c -> EmptyRecordPattern c
    RecordPattern fields -> RecordPattern fields
    Alias pat name -> Alias (fmap fast pat) name

    -- Types
    UnitType c -> UnitType c
    TypeVariable name -> TypeVariable name
    TypeConstruction ctor args -> TypeConstruction (fmap fctor ctor) (fmap (fmap fast) args)
    TypeParens typ -> TypeParens (fmap fast typ)
    TupleType typs -> TupleType (fmap (fmap fast) typs)
    RecordType base fields c ml -> RecordType base (fmap (fmap fast) fields) c ml
    FunctionType first rest ml -> FunctionType (fmap fast first) (fmap fast rest) ml


instance I.IFunctor (AST typeRef ctorRef varRef) where
    -- TODO: it's probably worth making an optimized version of this
    imap fast = mapAll id id id fast


-- mapType ::
--     (getType1 'TypeNK -> getType2 'TypeNK)
--     -> (forall kind. AST typeRef ctorRef varRef getType1 kind
--         -> AST typeRef ctorRef varRef getType2 kind
--        )
-- mapType ftyp =
--     imap fast
--     where
--         fast = \case
--             x -> ftyp x -- TODO: not right
