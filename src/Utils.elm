module Utils exposing (setTimeout, getWithDefault)

import Array exposing (Array)
import Time exposing (Time)
import Task
import Process


getWithDefault : a -> Int -> Array a -> a
getWithDefault default idx array =
    Maybe.withDefault default <| Array.get idx array


setTimeout : Time -> msg -> Cmd msg
setTimeout time msg =
    Process.sleep time
        |> Task.perform (\_ -> msg)
