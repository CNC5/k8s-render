#!/bin/bash

upload_port=4503
serve_port=3240
localhost="192.168.1.23"
rand_id=$(openssl rand -hex 12)
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

debug=true
info (){
    if [[ $debug == "true" ]]; then
        echo $1
    fi
}

error (){
    echo $1
}

re="^[0-9]+$"

if [[ -n $1 ]]; then
    if [[ -e $1 ]]; then
        blend_name=$1
        info "blend: $blend_name"
    else
        error "blend file does not exist, stopping"; exit 1
    fi
else
    error "no blend file specified, stopping"; exit 1
fi

cp $blend_name blend-$rand_id
if [[ -n $2 ]] && [[ -n $3 ]]; then
    if [[ $2 =~ $re ]] && [[ $3 =~ $re ]]; then
        s_frame=$2
        e_frame=$3
        info "using specified frame range"
    else
       error "specified frames are not numbers"; exit 1
    fi
else
    s_frame=1
    e_frame=1
    info "using default frame range"
fi

python3 -m http.server $serve_port &
tx_pid=$!
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
      args: -
        apk update &&
        apk add blender &&
        blender -b /workdir/blend -E CYCLES -o /workdir
        -noaudio -s $s_frame -e $e_frame
        -a -- --cycles-device CPU &&
        tar -zcpvf output.tar.gz /workdir &&
        curl -X POST http://$localhost:$upload_port/upload -F "files=@output.tar.gz"
      volumeMounts:
      - name: workdir
        mountpath: /workdir
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
      args: ["apk update && apk add wget && wget $localhost:$serve_port/blend-$rand_id"]
      volumeMounts:
      - name: workdir
        mountpath: /workdir
  restartPolicy: Never
  volumes:
  - name: workdir

TEMPLATE
pod_name=$(kubectl create -f render-pod-$rand_id.yaml | cut -d " " -f 1)
info "spawned $pod_name"
rm render-pod-$rand_id.yaml
python3 -m uploadserver $upload_port &
rx_pid=$!
trap "kill $tx_pid; kill $rx_pid && exit 1" INT
trap "kill $tx_pid; kill $rx_pid && exit 1" TERM
until kubectl get pods $pod_name | grep Terminated ; do
    sleep 2
done
mv output.tar.gz $pod_name-output.tar.gz
