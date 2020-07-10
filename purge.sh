#!/bin/bash
# Switch subscription to MPH project
sh switch_sub.sh
# Clean up namespace jhub
kubectl delete pvc --all -n jhub
kubectl delete pv --all -n jhub
kubectl delete namespace jhub
