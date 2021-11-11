module Update.Lifter exposing
    ( Lifter
    , compose
    , run
    )

{-| Helper module to lift `Update`s.

@docs Lifter
@docs compose
@docs run

-}

import Update exposing (Update)


{-| -}
type alias Lifter a b =
    { get : a -> b
    , set : b -> a -> a
    }


{-| -}
compose : Lifter a b -> Lifter b c -> Lifter a c
compose l1 l2 =
    { get = l1.get >> l2.get
    , set =
        \c a ->
            l1.get a
                |> l2.set c
                |> (\b -> l1.set b a)
    }


{-| Alternative to `Update.child`, but more scalable.
-}
run : Lifter a b -> Update b msg -> Update a msg
run lifter =
    Update.child lifter.get lifter.set
