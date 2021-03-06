port module Timers exposing
    ( Timers
    , init
    , initDelay
    , playSound
    , startDelayTimer
    , tick
    )

{-| Timers and Sounds

    Chip-8 provides 2 timers, a delay timer and a sound timer.

    The delay timer is active whenever the delay timer register (DT) is
    non-zero. This timer does nothing more than subtract 1 from the value of DT
    at a rate of 60Hz. When DT reaches 0, it deactivates.

-}

import Msg exposing (Msg(..))
import Process
import Registers exposing (Registers)
import Task


type alias Delay =
    { running : Bool
    , tickLength : Float
    }


initDelay : Delay
initDelay =
    { running = False
    , tickLength = (1 / 60) * 1000 -- 60Hz
    }


isRunning : Delay -> Bool
isRunning delay =
    delay.running


setRunning : Bool -> Delay -> Delay
setRunning running delay =
    { delay | running = running }


getTickLength : Delay -> Float
getTickLength delay =
    delay.tickLength


type alias Timers =
    { delay : Delay }


init : Timers
init =
    { delay = initDelay }


getDelay : Timers -> Delay
getDelay timers =
    timers.delay


setDelay : Delay -> Timers -> Timers
setDelay delay timers =
    { timers | delay = delay }


{-| Start the delay timer
-}
startDelayTimer : Registers -> Timers -> ( ( Registers, Timers ), Cmd Msg )
startDelayTimer registers timers =
    if not (timers |> getDelay |> isRunning) then
        let
            flip f a b =
                f b a

            updatedTimers =
                timers
                    |> getDelay
                    |> setRunning True
                    |> (setDelay |> flip) timers
        in
        tick registers updatedTimers

    else
        ( ( registers, timers ), Cmd.none )


{-| Performs a tick of the delay timer
-}
tick : Registers -> Timers -> ( ( Registers, Timers ), Cmd Msg )
tick registers timers =
    let
        delay =
            timers |> getDelay

        delayTimer =
            registers |> Registers.getDelayTimer
    in
    if isRunning delay && delayTimer > 0 then
        ( ( registers |> Registers.setDelayTimer (delayTimer - 1), timers )
        , setTimeout delay.tickLength DelayTick
        )

    else
        ( ( registers, setDelay (setRunning False delay) timers )
        , Cmd.none
        )


setTimeout : Float -> msg -> Cmd msg
setTimeout time msg =
    Process.sleep time
        |> Task.perform (\_ -> msg)


{-| Start playing the sound
-}
port playSound : Int -> Cmd msg
