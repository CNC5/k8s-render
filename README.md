a simple CLI tool enabling you to render Blender scenes on your Kubernetes cluster

example:
```./main.sh mask.blend 30 3```<br>
this will render the scene from mask.blend, starting at frame 1 and ending at frame 30<br>
using 3 pods,<br>
first pod will do 9 frames<br>
second will do 9 frames<br>
third will do 11 frames<br>
