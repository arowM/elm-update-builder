module Update.Sequence exposing
    ( Sequence
    , run
    , Msg
    , Model
    , initModel
    , resolve
    , call
    , succeed
    , waitAgain
    , with
    , when
    , unless
    , on
    , onAnyOf
    , anyOf
    , onJust
    , onNothing
    , onOk
    , onErr
    )

{-| Run `Update`s sequentially.


# A Quick Sample

    import Update exposing (Update)
    import Update.Sequence as Sequence exposing (Sequence)

    type Value
        = Start
        | ClickNext
        | SubmitText
        | NeverUsed

    type Msg
        = SequenceMsg (Sequence.Msg Value)

    type alias Model =
        { sequence : Sequence.Model
        , notice : String
        , text : String
        }

    update : Msg -> Update Model Msg
    update (SequenceMsg msg) =
        Sequence.run
            { get = .sequence
            , set = \seq model -> { model | sequence = seq }
            }
            msg
            [ Sequence.on Start
                [ setNotice "Tutorial has started!"
                ]
            , Sequence.on ClickNext
                [ setNotice "The first next button is clicked."
                ]
            , Sequence.on ClickNext
                [ setNotice "The second next button is clicked."
                ]
            , \v -> Sequence.when (v == SubmitText) <| Sequence.with <| \{ text } ->
                if text == "" then
                    Sequence.waitAgain <|
                        setNotice "Invalid text. Retry!"
                else
                    Sequence.succeed <|
                        setNotice <| text ++ " is submitted."
            , Sequence.on ClickNext
                [ setNotice "The last next button is clicked."
                ]
            ]



    -- Helper functions

    setNotice : String -> Update Model msg
    setNotice notice = Update.modify <| \model -> { model | notice = notice }


    -- Test the update function


    model0 : Model
    model0 =
        { sequence = Sequence.initModel
        , notice = "initial"
        , text = "initial text"
        }

    model1 : Model
    model1 =
        Update.run
            (update <| SequenceMsg <| Sequence.resolve Start)
            model0
            |> Tuple.first


    model1.notice
    --> "Tutorial has started!"

    model2 : Model
    model2 =
        Update.run
            (update <| SequenceMsg <| Sequence.resolve ClickNext)
            model1
            |> Tuple.first

    model2.notice
    --> "The first next button is clicked."

    -- Notice that here we provide the very same event as previous.
    model3 : Model
    model3 =
        Update.run
            (update <| SequenceMsg <| Sequence.resolve ClickNext)
            model2
            |> Tuple.first


    model3.notice
    --> "The second next button is clicked."
    -- The result shows that we get the second notice rather than the first one.

    model4 : Model
    model4 =
        Update.run
            (update <| SequenceMsg <| Sequence.resolve SubmitText)
            { model3 | text = "" }
            |> Tuple.first

    model4.notice
    --> "Invalid text. Retry!"

    -- Notice that here we provides the resulting `model4`, but not the previous `model3` again.
    model5 : Model
    model5 =
        Update.run
            (update <| SequenceMsg <| Sequence.resolve SubmitText)
            { model4 | text = "valid text" }
            |> Tuple.first

    model5.notice
    --> "valid text is submitted."
    -- The result shows that we can retry the current `Sequence`.

    model6 : Model
    model6 =
        Update.run
            (update <| SequenceMsg <| Sequence.resolve <| ClickNext)
            model5
            |> Tuple.first


    model6.notice
    --> "The last next button is clicked."


# Core

@docs Sequence
@docs run
@docs Msg
@docs Model
@docs initModel


# Msg Constructors

@docs resolve


# Controllers

@docs call


# Primitive Constructors

@docs succeed
@docs waitAgain


# Handle conditions

@docs with
@docs when
@docs unless


# Handle cases

@docs on
@docs onAnyOf
@docs anyOf
@docs onJust
@docs onNothing
@docs onOk
@docs onErr

-}

import Task
import Update exposing (Update)
import Update.Lifter as Lifter exposing (Lifter)



-- Core


{-| -}
type Sequence model msg
    = Sequence (model -> Sequence_ model msg)


unSequence : model -> Sequence model msg -> Sequence_ model msg
unSequence model (Sequence f) =
    f model


type Sequence_ model msg
    = Succeed (Update model msg)
    | Fail (Update model msg)


{-| -}
type Model
    = Model
        { offset : Int
        }


takeOffset : Model -> Int
takeOffset (Model { offset }) =
    offset


{-| -}
type Msg value
    = Resolve value


{-| -}
initModel : Model
initModel =
    Model
        { offset = 0
        }


{-| -}
run : Lifter model Model -> Msg value -> List (value -> Sequence model msg) -> Update model msg
run l msg ls =
    case msg of
        Resolve v ->
            Update.with identity
                [ \model ->
                    List.drop (takeOffset <| l.get model) ls
                        |> List.head
                        |> Maybe.map
                            (\f -> f v |> (\(Sequence fSeq) -> fSeq model))
                        |> Maybe.withDefault (Fail Update.none)
                        |> (\seq ->
                                case seq of
                                    Succeed u ->
                                        Update.batch
                                            [ incOffset
                                                |> Lifter.run l
                                            , u
                                            ]

                                    Fail u ->
                                        u
                           )
                ]


bind : Update model msg -> value -> (value -> Sequence model msg) -> Sequence model msg -> Sequence model msg
bind modify v f seq =
    Sequence <|
        \model ->
            case unSequence model seq of
                Succeed u ->
                    Succeed u

                Fail u ->
                    case unSequence model (f v) of
                        Succeed u2 ->
                            Succeed <| Update.batch [ u, u2 ]

                        Fail _ ->
                            Fail <| Update.batch [ u, modify ]


incOffset : Update Model msg
incOffset =
    Update.modify <| \(Model model) -> Model { model | offset = model.offset + 1 }


{-| -}
resolve : value -> Msg value
resolve =
    Resolve



-- Primitive Constructors


{-| Construct a `Sequence` always succeeds with given `Update`s.
-}
succeed : Update model msg -> Sequence model msg
succeed u =
    Sequence <| \_ -> Succeed u


{-| Construct a `Sequence` always wait again after evaluating given `Update`s.
-}
waitAgain : Update model msg -> Sequence model msg
waitAgain u =
    Sequence <| \_ -> Fail u



-- Handle conditions


{-| -}
with : (model -> Sequence model msg) -> Sequence model msg
with f =
    Sequence <|
        \model ->
            unSequence model (f model)


{-| Succeed `Sequence` only if it meets the condition.

Otherwise, it `waitAgain` with `Update.none`.

-}
when : Bool -> Sequence model msg -> Sequence model msg
when b seq =
    if b then
        seq

    else
        waitAgain Update.none


{-| Succeed `Sequence` unless it meets the condition.

Otherwise, it `waitAgain` with `Update.none`.

-}
unless : Bool -> Sequence model msg -> Sequence model msg
unless =
    when << not



-- Handle cases


{-| Generate a Sequence that succeeds only under certain value.

It succeeds with `Update`s only if the fired message value is equals to its first argument, otherwise it `waitAgain` with `Update.none`.

-}
on : value -> List (Update model msg) -> value -> Sequence model msg
on target updates v =
    if v == target then
        succeed <| Update.batch updates

    else
        waitAgain Update.none


{-| Generate a Sequence that succeeds only under certain values.

It succeeds with `Update`s only if the fired message value is one of its first argument, otherwise it `waitAgain` with `Update.none`.

-}
onAnyOf : List value -> List (Update model msg) -> value -> Sequence model msg
onAnyOf vs updates v =
    if List.member v vs then
        succeed <| Update.batch updates

    else
        waitAgain Update.none


{-| Evaluate `Sequence`s from top to bottom.

Once a `Sequence` succeeds, it does not evaluate subsequent `Sequence`s.

    Sequence.anyOf
        [ Sequence.on ClickOk
            [ setNotice "Ok"
            ]
        , Sequence.on ClickNg
            [ setNotice "Ng"
            ]
        ]

-}
anyOf : List (value -> Sequence model msg) -> value -> Sequence model msg
anyOf ls v =
    List.foldl (bind Update.none v) (waitAgain Update.none) ls


{-| Generate a Sequence that succeeds only on `Just` values.

It succeeds with `Update`s only if the value is `Just`, otherwise it `waitAgain` with `Update.none`.

-}
onJust : List (a -> Update model msg) -> Maybe a -> Sequence model msg
onJust ls ma =
    case ma of
        Just a ->
            List.map (\f -> f a) ls
                |> Update.batch
                |> succeed

        Nothing ->
            waitAgain Update.none


{-| Generate a Sequence that succeeds only on `Nothing` values.

It succeeds with `Update`s only if the value is `Nothing`, otherwise it `waitAgain` with `Update.none`.

-}
onNothing : List (Update model msg) -> Maybe a -> Sequence model msg
onNothing ls ma =
    case ma of
        Nothing ->
            ls
                |> Update.batch
                |> succeed

        Just _ ->
            waitAgain Update.none


{-| Generate a Sequence that succeeds only on `Ok` values.

It succeeds with `Update`s only if the value is `Ok`, otherwise it `waitAgain` with `Update.none`.

-}
onOk : List (a -> Update model msg) -> Result err a -> Sequence model msg
onOk ls res =
    case res of
        Ok a ->
            List.map (\f -> f a) ls
                |> Update.batch
                |> succeed

        Err _ ->
            waitAgain Update.none


{-| Generate a Sequence that succeeds only on `Err` values.

It succeeds with `Update`s only if the value is `Err`, otherwise it `waitAgain` with `Update.none`.

-}
onErr : List (err -> Update model msg) -> Result err a -> Sequence model msg
onErr ls res =
    case res of
        Err err ->
            List.map (\f -> f err) ls
                |> Update.batch
                |> succeed

        Ok _ ->
            waitAgain Update.none


{-| -}
call : v -> Update model (Msg v)
call v =
    Update.push <|
        \_ ->
            Task.attempt
                (\_ -> resolve v)
                (Task.succeed ())
