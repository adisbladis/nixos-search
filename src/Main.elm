module Main exposing (main)

--exposing (UrlRequest(..))

import Browser
import Browser.Navigation
import ElasticSearch
import Html
    exposing
        ( Html
        , a
        , div
        , footer
        , header
        , img
        , li
        , text
        , ul
        )
import Html.Attributes
    exposing
        ( class
        , classList
        , href
        , src
        )
import Page.Home
import Page.Options
import Page.Packages
import RemoteData
import Route
import Url



-- MODEL


type alias Flags =
    { elasticsearchUrl : String
    , elasticsearchUsername : String
    , elasticsearchPassword : String
    }


type alias Model =
    { navKey : Browser.Navigation.Key
    , url : Url.Url
    , elasticsearch : ElasticSearch.Options
    , page : Page
    }


type Page
    = NotFound
    | Home Page.Home.Model
    | Packages Page.Packages.Model
    | Options Page.Options.Model


init :
    Flags
    -> Url.Url
    -> Browser.Navigation.Key
    -> ( Model, Cmd Msg )
init flags url navKey =
    let
        model =
            { navKey = navKey
            , url = url
            , elasticsearch =
                ElasticSearch.Options
                    flags.elasticsearchUrl
                    flags.elasticsearchUsername
                    flags.elasticsearchPassword
            , page = NotFound
            }
    in
    changeRouteTo model url



-- UPDATE


type Msg
    = ChangedUrl Url.Url
    | ClickedLink Browser.UrlRequest
    | HomeMsg Page.Home.Msg
    | PackagesMsg Page.Packages.Msg
    | OptionsMsg Page.Options.Msg


updateWith :
    (subModel -> Page)
    -> (subMsg -> Msg)
    -> Model
    -> ( subModel, Cmd subMsg )
    -> ( Model, Cmd Msg )
updateWith toPage toMsg model ( subModel, subCmd ) =
    ( { model | page = toPage subModel }
    , Cmd.map toMsg subCmd
    )


submitQuery :
    Model
    -> ( Model, Cmd Msg )
    -> ( Model, Cmd Msg )
submitQuery old ( new, cmd ) =
    let
        triggerSearch oldModel newModel msg makeRequest =
            if newModel.query /= Nothing then
                ( new
                , Cmd.batch
                    [ cmd
                    , makeRequest
                        new.elasticsearch
                        newModel.channel
                        (Maybe.withDefault "" newModel.query)
                        newModel.from
                        newModel.size
                        |> Cmd.map msg
                    ]
                )

            else
                ( new, cmd )
    in
    case ( old.page, new.page ) of
        ( Packages oldModel, Packages newModel ) ->
            triggerSearch oldModel newModel PackagesMsg Page.Packages.makeRequest

        ( NotFound, Packages newModel ) ->
            triggerSearch newModel newModel PackagesMsg Page.Packages.makeRequest

        ( Options oldModel, Options newModel ) ->
            triggerSearch oldModel newModel OptionsMsg Page.Options.makeRequest

        ( NotFound, Options newModel ) ->
            triggerSearch newModel newModel OptionsMsg Page.Options.makeRequest

        ( _, _ ) ->
            ( new, cmd )


changeRouteTo : Model -> Url.Url -> ( Model, Cmd Msg )
changeRouteTo model url =
    let
        newModel =
            { model | url = url }

        maybeRoute =
            Route.fromUrl url
    in
    case maybeRoute of
        Nothing ->
            ( { newModel
                | page = NotFound
              }
            , Cmd.none
            )

        Just Route.NotFound ->
            ( { newModel
                | page = NotFound
              }
            , Cmd.none
            )

        Just Route.Home ->
            -- Always redirect to /packages until we have something to show
            -- on the home page
            ( newModel, Browser.Navigation.pushUrl newModel.navKey "/packages" )

        Just (Route.Packages channel query showDetailsFor from size) ->
            Page.Packages.init channel query showDetailsFor from size
                |> updateWith Packages PackagesMsg newModel
                |> submitQuery newModel

        Just (Route.Options channel query showDetailsFor from size) ->
            Page.Options.init channel query showDetailsFor from size
                |> updateWith Options OptionsMsg newModel
                |> submitQuery newModel


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.page ) of
        ( ClickedLink urlRequest, _ ) ->
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , if url.fragment == Just "disabled" then
                        Cmd.none

                      else
                        Browser.Navigation.pushUrl model.navKey <| Url.toString url
                    )

                Browser.External href ->
                    ( model
                    , Browser.Navigation.load href
                    )

        ( ChangedUrl url, _ ) ->
            changeRouteTo model url

        ( HomeMsg subMsg, Home subModel ) ->
            Page.Home.update subMsg subModel
                |> updateWith Home HomeMsg model

        ( PackagesMsg subMsg, Packages subModel ) ->
            Page.Packages.update model.navKey subMsg subModel
                |> updateWith Packages PackagesMsg model

        ( OptionsMsg subMsg, Options subModel ) ->
            Page.Options.update model.navKey subMsg subModel
                |> updateWith Options OptionsMsg model

        ( _, _ ) ->
            -- Disregard messages that arrived for the wrong page.
            ( model, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    div []
        [ header []
            [ div [ class "navbar navbar-static-top" ]
                [ div [ class "navbar-inner" ]
                    [ div [ class "container" ]
                        [ a [ class "brand", href "https://search.nixos.org" ]
                            [ img [ src "https://nixos.org/logo/nix-wiki.png", class "logo" ] []
                            ]
                        , viewNavigation model.url
                        ]
                    ]
                ]
            ]
        , div [ class "container main" ]
            [ viewPage model
            , footer [] []
            ]
        ]


viewNavigation : Url.Url -> Html Msg
viewNavigation url =
    ul [ class "nav" ]
        (List.map
            (viewNavigationItem url)
            [ ( "/packages", "Packages" )
            , ( "/options", "Options" )
            ]
        )


viewNavigationItem :
    Url.Url
    -> ( String, String )
    -> Html Msg
viewNavigationItem url ( path, title ) =
    li
        [ classList [ ( "active", path == url.path ) ] ]
        [ a [ href path ] [ text title ] ]


viewPage : Model -> Html Msg
viewPage model =
    case model.page of
        NotFound ->
            div [] [ text "Not Found" ]

        Home _ ->
            div [] [ text "Welcome" ]

        Packages packagesModel ->
            Html.map (\m -> PackagesMsg m) <| Page.Packages.view packagesModel

        Options optionsModel ->
            Html.map (\m -> OptionsMsg m) <| Page.Options.view optionsModel



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , onUrlRequest = ClickedLink
        , onUrlChange = ChangedUrl
        , subscriptions = subscriptions
        , update = update
        , view =
            \m ->
                { title = "NixOS Search"
                , body = [ view m ]
                }
        }
