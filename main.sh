#!/bin/bash

show_help () {
echo ''
echo 'short help:'
echo 'positional args:'
echo '  0.blend file'
echo '  1.end frame'
echo '  2.number of pods to create'
echo ''
echo 'example:'
echo '  ./main.sh mask.blend 30 3'
echo '    will render the scene from mask.blend'
echo '    using 3 pods,'
echo '    first pod will do 9 frames'
echo '    second will do 9 frames'
echo '    third will do 11 frames'
}

upload_port=4503
serve_port=3240
localhost="192.168.1.23"
rand_id=$(openssl rand -hex 12)
debug=true

info (){
    if [[ $debug == "true" ]]; then
        echo $1
    fi
}

error (){
    echo $1
}

cleanup (){
    pool=$1
    info "running cleanup"
    kubectl delete pod $pod_pool
    kill $tx_pid
    kill $rx_pid
    rm blend-$rand_id
    for name in $pool; do
        rm $name.lock
    done
}

re="^[0-9]+$"
if netstat -tulpn | grep $upload_port ; then
    until ! netstat -tulpn | grep $upload_port; do
        let "upload_port=upload_port+1"
    done
fi

if netstat -tulpn | grep $serve_port ; then
    until ! netstat -tulpn | grep $serve_port; do
        let "serve_port=serve_port+1"
    done
fi

if [[ -n $1 ]]; then
    if [[ -e $1 ]]; then
        blend_name=$1
        info "blend: $blend_name"
    else
        error "blend file does not exist, stopping"; show_help; exit 1
    fi
else
    error "no blend file specified, stopping"; show_help; exit 1
fi

cp $blend_name blend-$rand_id
if [[ -n $2 ]]; then
    if [[ $2 =~ $re ]]; then
        s_frame=$2
        info "using specified frame range"
    else
        error "specified frames are not numbers"; exit 1
    fi
else
    s_frame=1
    e_frame=1
    info "using default frame range"
fi

if [[ -n $3 ]]; then
    if [[ $3 =~ $re ]]; then
        parts=$3
        info "using specified pod count"
    else
        error "specified pod count is NaN"; exit 1
    fi
else
    parts=1
    info "using default pod count (1)"
fi

spawn_pod () {
s_frame=$1
e_frame=$2
tx_port=$3
rx_port=$4
id=$5
cat <<TEMPLATE >> render-pod-$rand_id.yaml
apiVersion: v1
kind: Pod
metadata:
  generateName: render-instance-
spec:
  containers:
    - name: renderer
      image: alpine
      command: ["/bin/sh","-c"]
      args: ["apk update && apk add curl blender && blender -b /workdir/blend -E CYCLES -o /workdir/ -noaudio -s $s_frame -e $e_frame -a -- --cycles-device CPU && tar -zcpvf $id-output.tar.gz /workdir && curl -X POST http://$localhost:$rx_port/upload -F 'files=@$id-output.tar.gz'"]
      volumeMounts:
      - name: workdir
        mountPath: /workdir
      resources:
        requests:
          cpu: 3
          memory: 8Gi
        limits:
          cpu: 4
          memory: 12Gi
  initContainers:
    - name: downloader
      image: alpine
      command: ["/bin/sh","-c"]
      args: ["apk update && apk add wget && wget $localhost:$tx_port/blend-$rand_id -O /workdir/blend"]
      volumeMounts:
      - name: workdir
        mountPath: /workdir
  restartPolicy: Never
  volumes:
  - name: workdir

TEMPLATE
pod_name=$(kubectl create -f render-pod-$rand_id.yaml | cut -d " " -f 1 | cut -d "/" -f 2)
echo "$pod_name"
rm render-pod-$rand_id.yaml
}

frame_distribute () {
    total=$1
    parts=$2
    python3 -m http.server $serve_port &
    tx_pid=$!

    let 'part=total/parts'
    point=1
    prev_point=0

    if [[ $parts -gt 1 ]]; then
        for i in $( seq 1 $((parts-1)) )
        do
            let 'point=prev_point+part'
            pod_name=$(spawn_pod $((prev_point+1)) $point $serve_port $upload_port $i)
            prev_point=$point
            echo $pod_name > $pod_name.lock
            pod_pool="$pod_pool $pod_name")
        done
    fi
    pod_name=$(spawn_pod $((prev_point+1)) $total $server_port $upload_port $parts)
    echo $pod_name > $pod_name.lock
    pod_pool="$pod_pool $pod_name"
    echo $pod_pool
    python3 -m uploadserver $upload_port &
    rx_pid=$!
    trap "cleanup; exit 1" INT
    trap "cleanup; exit 1" TERM
    until [[ $(kubectl get pods $pod_pool | grep Completed | wc -l) = $parts ]]; do
        sleep 2
    done
    cleanup $pod_pool
}

frame_distribute $2 $3
