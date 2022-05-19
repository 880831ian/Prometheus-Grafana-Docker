#!/bin/bash

docker="docker exec nginx"

for i in {1..10}
do
	$docker curl http://nginx:8080/stub_status -s
done
