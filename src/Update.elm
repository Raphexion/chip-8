module Update exposing (update)

import Array exposing (Array)
import Bytes exposing (Bytes)
import Bytes.Decode as Decode exposing (Decoder, Step(..))
import Dict
import Display
import FetchDecodeExecuteLoop
import Flags exposing (Flags)
import Http exposing (Metadata, Response(..))
import KeyCode exposing (KeyCode)
import Keypad
import List.Extra as List
import Memory
import Model exposing (Model)
import Msg exposing (Msg(..))
import Registers exposing (Registers)
import Timers
import Types exposing (Value8Bit)
import Utils exposing (noCmd)


addKeyCode : Maybe KeyCode -> Model -> ( Model, Cmd Msg )
addKeyCode maybeKeyCode model =
    case maybeKeyCode of
        Just keyCode ->
            let
                newKeypad =
                    model
                        |> Model.getKeypad
                        |> Keypad.addKeyPress keyCode
            in
            model
                |> Model.setKeypad newKeypad
                |> checkIfWaitingForKeyPress keyCode

        _ ->
            ( model, Cmd.none )


removeKeyCode : Maybe KeyCode -> Model -> ( Model, Cmd Msg )
removeKeyCode maybeKeyCode model =
    case maybeKeyCode of
        Just keyCode ->
            let
                newKeypad =
                    model
                        |> Model.getKeypad
                        |> Keypad.removeKeyPress keyCode
            in
            model |> Model.setKeypad newKeypad |> noCmd

        Nothing ->
            ( model, Cmd.none )


checkIfWaitingForKeyPress : KeyCode -> Model -> ( Model, Cmd Msg )
checkIfWaitingForKeyPress keyCode model =
    case model |> Model.getFlags |> Flags.getWaitingForInputRegister of
        Just registerX ->
            let
                newFlags =
                    model
                        |> Model.getFlags
                        |> Flags.setWaitingForInputRegister Nothing

                newRegisters =
                    model
                        |> Model.getRegisters
                        |> Registers.setDataRegister registerX (KeyCode.nibbleValue keyCode)
            in
            model
                |> Model.setFlags newFlags
                |> Model.setRegisters newRegisters
                |> noCmd

        _ ->
            model
                |> noCmd


delayTick : Model -> ( Model, Cmd Msg )
delayTick model =
    let
        ( ( newRegisters, newTimers ), cmd ) =
            Timers.tick
                (model |> Model.getRegisters)
                (model |> Model.getTimers)
    in
    ( model
        |> Model.setRegisters newRegisters
        |> Model.setTimers newTimers
    , cmd
    )


clockTick : Model -> ( Model, Cmd Msg )
clockTick model =
    let
        flags =
            model |> Model.getFlags

        running =
            flags |> Flags.isRunning

        waitingForInput =
            flags |> Flags.isWaitingForInput

        speed =
            2
    in
    if running == True && waitingForInput == False then
        model |> FetchDecodeExecuteLoop.tick speed

    else
        ( model, Cmd.none )


selectGame : String -> Model -> ( Model, Cmd Msg )
selectGame gameName model =
    let
        selectedGame =
            List.find (.name >> (==) gameName) model.games
    in
    ( Model.initModel
        |> Model.setSelectedGame selectedGame
    , loadGame gameName
    )


loadGame : String -> Cmd Msg
loadGame game =
    Http.get
        { url = "/roms/" ++ game
        , expect = Http.expectBytesResponse LoadedGame decodeBytesResponse
        }


decodeBytesResponse : Response Bytes -> Result Http.Error (Array Value8Bit)
decodeBytesResponse response =
    case response of
        Http.BadUrl_ url ->
            Err (Http.BadUrl url)

        Http.Timeout_ ->
            Err Http.Timeout

        Http.NetworkError_ ->
            Err Http.NetworkError

        Http.BadStatus_ metadata body ->
            Err (Http.BadStatus metadata.statusCode)

        Http.GoodStatus_ metadata bytes ->
            case Decode.decode (romDecoder (Bytes.width bytes)) bytes of
                Just rom ->
                    Ok rom

                Nothing ->
                    Err (Http.BadBody "Could not decode byte payload")


romDecoder : Int -> Decoder (Array Value8Bit)
romDecoder width =
    Decode.map Array.fromList <| byteListDecoder Decode.unsignedInt8 width


byteListDecoder : Decoder a -> Int -> Decoder (List a)
byteListDecoder decoder width =
    Decode.loop ( width, [] ) (listStep decoder)


listStep : Decoder a -> ( Int, List a ) -> Decoder (Step ( Int, List a ) (List a))
listStep decoder ( n, xs ) =
    if n <= 0 then
        Decode.succeed (Done (List.reverse xs))

    else
        Decode.map (\x -> Loop ( n - 1, x :: xs )) decoder


reloadGame : Model -> ( Model, Cmd Msg )
reloadGame model =
    case model |> Model.getSelectedGame of
        Just game ->
            let
                freshModel =
                    Model.initModel

                ( newModel, cmd ) =
                    selectGame game.name freshModel
            in
            ( newModel
            , Cmd.batch
                [ freshModel |> Model.getDisplay |> Display.drawDisplay
                , cmd
                ]
            )

        Nothing ->
            model |> noCmd


readProgram : Result Http.Error (Array Value8Bit) -> Model -> ( Model, Cmd Msg )
readProgram programBytesResult model =
    case programBytesResult of
        Err error ->
            -- TODO: Report error
            ( model, Cmd.none )

        Ok programBytes ->
            let
                programStart =
                    512

                newMemory =
                    List.indexedFoldl
                        (\idx -> Memory.setCell (programStart + idx))
                        (model |> Model.getMemory)
                        (programBytes |> Array.toList)

                newRegisters =
                    model
                        |> Model.getRegisters
                        |> Registers.setAddressRegister 0
                        |> Registers.setProgramCounter programStart

                newFlags =
                    model |> Model.getFlags |> Flags.setRunning True
            in
            model
                |> Model.setMemory newMemory
                |> Model.setRegisters newRegisters
                |> Model.setFlags newFlags
                |> noCmd


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        KeyDown maybeKeyCode ->
            model |> addKeyCode maybeKeyCode

        KeyUp maybeKeyCode ->
            model |> removeKeyCode maybeKeyCode

        KeyPress keyCode ->
            model |> noCmd

        DelayTick ->
            model |> delayTick

        ClockTick _ ->
            model |> clockTick

        SelectGame gameName ->
            model |> selectGame gameName

        ReloadGame ->
            model |> reloadGame

        LoadedGame gameBytesResult ->
            model |> readProgram gameBytesResult
