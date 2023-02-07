#!/bin/bash

spawn_pod () {
    echo "spawned pod with params $@"
}

frame_distribute () {
    total=$1
    parts=$2

    let 'part=total/parts'
    point=1
    prev_point=0

    for i in $( seq 1 $((parts-1)) )
    do
        let 'point=prev_point+part'
        spawn_pod $((prev_point+1)) $point
        prev_point=$point
    done
    spawn_pod $((prev_point+1)) $total
}

frame_distribute $@
