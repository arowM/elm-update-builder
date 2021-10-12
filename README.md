# elm-update-builder

[![Build Status](https://travis-ci.org/arowM/elm-update-builder.svg?branch=main)](https://travis-ci.org/arowM/elm-update-builder)
[日本語版（Japanese version）](https://qiita.com/items/54818822ea8bf25108fe)

DEPRECATED! [elm-thread](https://package.elm-lang.org/packages/arowM/elm-thread/latest/) has been released!


Compose a complex update function from primitive functions.

# A Quick Example

Here is a little example how elm-update-builder can build update function so that the process flow is easy to understand.

```elm
    Update.with (FD.run formDecoder)
        [ Update.onErr
            [ \_ -> showError
            ]
        , Update.onOk
            [ submit
            , \_ -> makeFormBusy
            ]
        ]
```

# Drawbacks of conventional update functions

In TEA, conventional update functions have the following type:

```
update : msg -> model -> (model, Cmd msg)
```

Not so bad, but it has some drawbacks. To explain the drawbacks, we will introduce a sample application. Then, let's use elm-update-builder to solve the defects of the conventional update functions.

# About the sample application

Say we have a form to register personal information for goats. Let's define the model:

```elm
type alias Model =
    { isBusy : Bool -- Is the form busy to submit?
    , showError : Bool -- Should we display errors on the page?
    , name : String -- Input for the goat name
    , color : String -- Input for the coat color of the goat
    }

init : ( Model, Cmd Msg )
init =
    ( { isBusy = False
      , showError = False
      , name = ""
      , color = ""
      }
    , Cmd.none
    )
```

As you can see from the model definition, this form has input fields for name and coat color. Each of the input fields is required, and we want to display an error if the field is blank. But what about the moment when the user opens the form? Inputs for the name and coat color are blank, which means that if we validate the form as it is, the user will see an error. It's not user friendly to tell "you're wrong" when user just opens a form. It is the reason why we have `showError` in the model. The `showError` is a flag that says, "Show errors on the screen". The value is `False` by default not to show errors on loading the app, and changed to be `True` on pressing the submit button. The other flag `isBusy` represents whether the message is being sent or not. It prevents the various glitches caused by short-tempered goats who hit the send button repeatedly with their two hoofs.

![user](https://user-images.githubusercontent.com/1481749/115139784-df695100-a06e-11eb-965a-5d769d5455f1.jpg)

# Describe the process flow

Next, in order to realize nice user experieance, let's first try to describe the process flow in natural languages. If we started by writing the program without doing so, we would have a big regression after we finished writing the program. If we write it in natural languages first, it is easy to ask our team members to review and revise it.

Here we describe the process flow when the submit button is pressed:

```markdown
* Check if inputs are valid
    * When invalid:
        * Change to display errors
    * When valid:
        * Submit the answers to the backend server
        * Make form status busy
```

# Conventional approach

To realize this process flow, our update function will be as follows:

```elm
import Form.Decoder as FD


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SubmitForm ->
            case FD.run formDecoder model of
                Ok profile ->
                    ( { model
                        | isBusy = True
                      }
                    , submit profile
                    )

                Err _ ->
                    ( { model
                        | showError = True
                      }
                    , Cmd.none
                    )

submit : Profile -> Cmd Msg
submit profile = Debug.todo "Cmd to submit profile"
```

The module we are importing on the top is [arowM/elm-form-decoder](http://localhost:8000/packages/arowM/elm-form-decoder/latest), which is a handy library that can validate forms and also convert them into data for submission. It is definitly nice to use if you creates forms. For more details, please see [Form Decoding: the next era of the Form Validation](https://arow.info/posts/2019/form-decoding/).

It is not hard to understand the process flow because this sample is relatively simple, but it would be harder if the flow grows to be complex. This is the drawback of the conventional update functions which elm-update-builder can solve.

# New approach with update-builder

With elm-update builder, we can express the process flow more intuitively. The alternative program as follows:

```elm
import Form.Decoder as FD
import Update exposing (Update)


update : Msg -> Update Model Msg
update msg =
    case msg of
        SubmitForm ->
            Update.with (FD.run formDecoder)
                [ Update.onErr
                    [ \_ -> showError
                    ]
                , Update.onOk
                    [ submit
                    , \_ -> makeFormBusy
                    ]
                ]

showError : Update Model Msg
showError = Update.modify <| \model -> { model | showError = True }

makeFormBusy : Update Model Msg
makeFormBusy = Update.modify <| \model -> { model | isBusy = True }

submit : Profile -> Update Model Msg
submit profile = Update.push <| \model -> Debug.todo "Cmd to submit profile"
```

The process flow is now much clear. Let's compare it again with the previous flow description. You can see that the program is almost verbatim.

```markdown
* Check if inputs are valid
    * When invalid:
        * Change to display errors
    * When valid:
        * Submit the answers to the backend server
        * Make form status busy
```

```elm
Update.with (FD.run formDecoder)
    [ Update.onErr
        [ \_ -> showError
        ]
    , Update.onOk
        [ submit
        , \_ -> makeFormBusy
        ]
    ]
```

Process flow is changed often as the business logic and UI changes. The fact that elm-update-builder can express process flow as it is means the elm-update-builder is a powerful weapon in application development.

# Convert to the conventional update function

No matter how well it express the process flow, it is useless if the new version of update function cannot be used in The Elm Architecture. Don't worry. It can be done simply by using the `Update.run` function.

```elm
run : Update model msg -> model -> ( model, Cmd msg )
```

Use the `run` function when passing update function to `Browser.element` and so on.

```elm
main : Program flags model msg
main =
    element
        { init = init
        , view = view
        , update = Update.run << update
        , subscriptions = subscriptions
        }

update : msg -> Update model msg
update = Debug.todo "update function with `Update`"
```
