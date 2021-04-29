module Update exposing
    ( Update
    , run
    , batch
    , none
    , modify
    , push
    , init
    , when
    , unless
    , whenNothing
    , whenJust
    , whenOk
    , whenErr
    , with
    , on
    , onNothing
    , onJust
    , onOk
    , onErr
    , map
    , child
    , maybeChild
    )

{-| Module providing a way to build scalable update function.
It enables you to build a complex update function by composing primitive functions.


# Core

@docs Update
@docs run
@docs batch


# Primitive Updates

@docs none
@docs modify
@docs push
@docs init


# Handle conditions

@docs when
@docs unless
@docs whenNothing
@docs whenJust
@docs whenOk
@docs whenErr


# Handle cases

@docs with
@docs on
@docs onNothing
@docs onJust
@docs onOk
@docs onErr


# Lower level functions

@docs map
@docs child
@docs maybeChild

-}


{-| Alternative type for update function.

    update : msg -> Update model msg

-}
type Update model msg
    = Update (model -> ( model, Cmd msg ))


{-| Evaluate to a model-cmd pair.

It is for converting to the normal update function.
e.g.,

    main : Program flags model msg
    main =
        element
            { init = init
            , view = view
            , update = Update.run << update
            , subscriptions = subscriptions
            }

    update : msg -> Update model msg
    update =
        ...

-}
run : Update model msg -> model -> ( model, Cmd msg )
run (Update f) a =
    f a


{-| Lift `Update` for a child model to one for the parent model.

e.g.,

    type alias Model =
        { child1 : ChildModel
        }

    type alias ChildModel =
        { foo : String
        }

    child1Update : Update ChildModel msg
    child1Update =
        Debug.todo "Update for the `ChildModel`"

    update : Update Model msg
    update =
        child
            .child1
            (\c model -> { model | child1 = c })
            child1Update

-}
child : (b -> a) -> (a -> b -> b) -> Update a msg -> Update b msg
child take put (Update f) =
    Update <|
        \b ->
            let
                ( model, cmd ) =
                    f (take b)
            in
            ( put model b
            , cmd
            )


{-| Same as `child` but do nothing if first argument becomes to `Nothing`.
It is usefull for handling page updates of SPA.

e.g.,

    type alias Model =
        { page : Page
        }

    type Page
        = Page1 Page1Model
        | Page2 Page2Model

    type alias Page1Model =
        { foo : String
        }

    type alias Page2Model =
        { bar : Int
        }

    page1Update : Update Page1Model msg
    page1Update =
        Debug.todo "update function for `Page1`."

    update : Update Model msg
    update =
        Update.with identity
            [ \{ page } ->
                case page of
                    Page1 page1 ->
                        page1Update
                            (\model ->
                                case model.page of
                                    Page1 a ->
                                        Just a

                                    _ ->
                                        Nothing
                            )
                            (\p model ->
                                case model.page of
                                    Page1 _ ->
                                        { model | page = Page1 p }

                                    _ ->
                                        model
                            )
                            page1Update

                    _ ->
                        Debug.todo ""
            ]

-}
maybeChild : (b -> Maybe a) -> (a -> b -> b) -> Update a msg -> Update b msg
maybeChild take put (Update f) =
    Update <|
        \b ->
            case Maybe.map f <| take b of
                Nothing ->
                    ( b, Cmd.none )

                Just ( model, cmd ) ->
                    ( put model b
                    , cmd
                    )


{-| Do nothing.
-}
none : Update model msg
none =
    Update <|
        \model ->
            ( model
            , Cmd.none
            )


{-| -}
map : (a -> b) -> Update model a -> Update model b
map g (Update f) =
    Update <|
        \a ->
            f a
                |> Tuple.mapSecond (Cmd.map g)


{-| Primitive `Update` that modifies Model.
-}
modify : (model -> model) -> Update model msg
modify f =
    Update <|
        \model ->
            ( f model
            , Cmd.none
            )


{-| Primitive `Update` that pushes a `Cmd`.
-}
push : (model -> Cmd msg) -> Update model msg
push cmd =
    Update <|
        \model ->
            ( model, cmd model )


{-| An `Update` to initialize.

    init f =
        batch
            [ modify (f >> Tuple.first)
            , push (f >> Tuple.second)
            ]

-}
init : (model -> ( model, Cmd msg )) -> Update model msg
init f =
    batch
        [ modify (f >> Tuple.first)
        , push (f >> Tuple.second)
        ]



-- Condition


{-| Evaluate `Update` only if it meets the condition.
-}
when : Bool -> List (Update model msg) -> Update model msg
when p updates =
    if p then
        batch updates

    else
        none


{-| Evaluate `Update` unless it meets the condition.
-}
unless : Bool -> List (Update model msg) -> Update model msg
unless =
    when << not


{-| Evaluate `Update` only if the first argument value is `Nothing`.
-}
whenNothing : Maybe a -> List (Update model msg) -> Update model msg
whenNothing ma ls =
    onNothing ls ma


{-| Evaluate `Update` only if the first argument value is `Just`.
-}
whenJust : Maybe a -> List (a -> Update model msg) -> Update model msg
whenJust ma ls =
    onJust ls ma


{-| Evaluate `Update` only if the first argument value is `Ok`.
-}
whenOk : Result err a -> List (a -> Update model msg) -> Update model msg
whenOk res ls =
    onOk ls res


{-| Evaluate `Update` only if the first argument value is `Err`.
-}
whenErr : Result err a -> List (err -> Update model msg) -> Update model msg
whenErr res ls =
    onErr ls res



-- Cases


{-| Branch the update process according to the situation.

    type alias Model =
        { foo : String
        , bar : Maybe Int
        }

    updateWithFoo : Update Model msg
    updateWithFoo =
        with .foo
            [ on String.isEmpty
                [ Update.modify <| \model ->
                    { model | foo = "empty" }
                ]
            ]

    updateWithBar : Update Model msg
    updateWithBar =
        with .bar
            [ onJust
                [ \n -> Update.modify <| \model ->
                    { model | foo = String.fromInt n }
                ]
            ]


    updateWithBarSequentially : Update Model msg
    updateWithBarSequentially =
        with .bar
            [ onJust
                [ \n -> Update.modify <| \model ->
                    { model | bar = Nothing }
                ]
            , onNothing
                [ Update.modify <| \model ->
                    { model | foo = "bar has changed" }
                ]
            ]


    run updateWithFoo
        { foo = ""
        , bar = Nothing
        }
            |> Tuple.first
    --> { foo = "empty", bar = Nothing }

    run updateWithFoo
        { foo = "foo"
        , bar = Nothing
        }
            |> Tuple.first
    --> { foo = "foo", bar = Nothing }

    run updateWithBar
        { foo = "foo"
        , bar = Just 4
        }
            |> Tuple.first
    --> { foo = "4", bar = Just 4 }

    run updateWithBarSequentially
        { foo = "foo"
        , bar = Just 4
        }
            |> Tuple.first
    --> { foo = "bar has changed", bar = Nothing }

-}
with : (model -> a) -> List (a -> Update model msg) -> Update model msg
with get =
    List.foldl (\f acc -> andThenWith get f acc) none


{-| Evaluate `Update` only if it matches the case.
-}
on : (a -> Bool) -> List (Update model msg) -> a -> Update model msg
on p updates a =
    if p a then
        batch updates

    else
        none


{-| Evaluate `Update` only if the case is `Nothing`.
-}
onNothing : List (Update model msg) -> Maybe a -> Update model msg
onNothing updates ma =
    case ma of
        Nothing ->
            batch updates

        Just _ ->
            none


{-| Evaluate `Update` only if the case is `Just`.
-}
onJust : List (a -> Update model msg) -> Maybe a -> Update model msg
onJust ls ma =
    case ma of
        Nothing ->
            none

        Just a ->
            ls
                |> List.map (\f -> f a)
                |> batch


{-| Evaluate `Update` only if the case is `Ok`.
-}
onOk : List (a -> Update model msg) -> Result err a -> Update model msg
onOk ls res =
    case res of
        Ok a ->
            ls
                |> List.map (\f -> f a)
                |> batch

        Err _ ->
            none


{-| Evaluate `Update` only if the case is `Err`.
-}
onErr : List (err -> Update model msg) -> Result err a -> Update model msg
onErr ls res =
    case res of
        Ok _ ->
            none

        Err err ->
            ls
                |> List.map (\f -> f err)
                |> batch


then_ : Update model msg -> Update model msg -> Update model msg
then_ (Update f) (Update g) =
    Update <|
        \a ->
            let
                ( model, cmd ) =
                    g a

                ( model2, cmd2 ) =
                    f model
            in
            ( model2
            , Cmd.batch [ cmd, cmd2 ]
            )


andThenWith : (model -> a) -> (a -> Update model msg) -> Update model msg -> Update model msg
andThenWith get fUpdate (Update g) =
    Update <|
        \x ->
            let
                ( model, cmd ) =
                    g x

                (Update f) =
                    fUpdate (get model)

                ( model2, cmd2 ) =
                    f model
            in
            ( model2
            , Cmd.batch [ cmd, cmd2 ]
            )


{-| When you need to evaluate a couple `Update`s, you can batch them together. Each is evaluated from top to bottom.

    type alias Model = { foo : String }

    myUpdate : Update Model msg
    myUpdate =
        batch
            [ modify (\m -> { m | foo = m.foo ++ "-1" })
            , modify (\m -> { m | foo = m.foo ++ "-2" })
            ]

    run myUpdate { foo = "bar" }
        |> Tuple.first
    --> { foo = "bar-1-2" }

-}
batch : List (Update model msg) -> Update model msg
batch =
    List.foldl (\a acc -> then_ a acc) none
