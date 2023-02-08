#!/bin/bash

kubectl delete pod $(cat render-instance-*.lock)
rm render-instance-*.lock *-output.tar.gz
