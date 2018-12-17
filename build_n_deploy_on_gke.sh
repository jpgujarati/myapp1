#!/bin/bash
set -x
#kubectl delete service hello-app-web
#kubectl delete deployment hello-app-web
#gcloud container clusters delete --quiet hello-app-cluster
#exit
APP_NAME='hello-app'
GKE_DEPLOYMENT_NAME='hello-app-web'
MESSAGE=$(cat config.json | grep message | awk -F '"' '{print $4 }')
CONTAINER_PORT=$(cat config.json | grep port | awk -F : '{print $2 }' | sed 's|[^0-9]||g' )
IMAGE_TAG=$1
echo
echo "Application/Container Port : ${CONTAINER_PORT}"
echo
echo "UI Message                 : ${MESSAGE}"
echo

HOST_PORT='4000'
LOAD_BALANCER_PORT='80'
# get google cloud account projectid 
echo "#########  Getting the google cloud project id  #############"
echo
export PROJECT_ID="$(gcloud config get-value project -q)"
if [ $? = 0 ]
  then
    echo "google cloud project id is: ${PROJECT_ID}"
  else
    echo "Error: unable to get google cloud project id ... Exiting the script"
    exit 1 
fi

IMAGE_NAME="gcr.io/${PROJECT_ID}/${APP_NAME}"
# build docker image for nodejs application
echo
echo "############## Building the docker image ####################"
echo
echo "imageID:Tag : ${IMAGE_NAME}:${IMAGE_TAG}"


sudo docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
#docker build -t gcr.io/${PROJECT_ID}/${APP_NAME}:${1} . 
if [ $? = 0 ]
  then
    echo
    echo "################## Docker Image build sucessfully #######"
    echo "################## Listing all Docker images ############"
    echo
    sudo docker images
    echo
  else
    echo
    echo "#######Error: docker image build failed ... Exiting the script ###########" >&2
    echo
    echo "########## Listing all Docker images ##########"
    echo
    sudo docker images
    echo
    exit 1
fi

                
# configure Docker command-line tool to authenticate to Container Registry 
# this is a one time configuration
#gcloud auth configure-docker

sleep 3s

echo
echo "##################### Running and testing image locally before deploying on GKE #######"
echo
sudo docker run --rm -d -p ${HOST_PORT}:${CONTAINER_PORT} ${IMAGE_NAME}:${IMAGE_TAG} 
sleep 10s
CURL_RESPONSE=$(curl localhost:${HOST_PORT})
echo "Expected Message: ${MESSAGE}"
echo "Curl Response   : ${CURL_RESPONSE}"

if [ "${CURL_RESPONSE}" = "${MESSAGE}" ]                
  then
    echo
    echo "############# Application is succesfully deployed locally ####################3"
    echo
  else
    echo
    echo "############# ERROR : application failed to deploy locally. Exiting deployment script #############" >&2
    echo
    exit 1
fi

echo

sudo docker ps

echo
echo '#################################################################'
echo '########### Stopping the container deployed locally #############'
echo '#################################################################'
echo

echo  '   ######### list running containers before stopping the container  #########'
echo
sudo docker ps

export CONTAINER_ID="$(sudo docker ps | grep ${IMAGE_NAME}:${IMAGE_TAG} | awk -F " " '{print $1}')"
echo "Container ID : ${CONTAINER_ID}"

sudo docker stop ${CONTAINER_ID}

echo
echo  '   ######### list running containers after stopping the container  #########'
echo

sudo docker ps

echo
echo "####################push image to google container registry ######################"
echo
sudo docker push ${IMAGE_NAME}:${IMAGE_TAG} 
sleep 3s
 
echo
echo '#################################################################'
echo '########### Deleting Local copy of the Image #############'
echo '#################################################################'
echo
echo  '   ######### list docker images before deleting the image#########'
echo
sudo docker images
export IMAGE_ID="$(sudo docker images | grep "${IMAGE_NAME}   ${IMAGE_TAG}" | awk -F " " '{print $3}')"
echo "IMAGE ID : ${IMAGE_ID}"

sudo docker image rm ${IMAGE_ID}

echo
echo  '   ######### list docker images after deleting the image #########'
echo
sudo docker images
echo
 
#exit 

echo
echo "########### gcloud compute instances list - before cluster creation #############"
echo

gcloud compute instances list

echo
echo '############################################################################################'
echo "########### Creating a Google Kubternetes Engine (GKE) Cluster for ${APP_NAME} #############"
echo '############################################################################################'
echo

gcloud container clusters create ${APP_NAME}-cluster --num-nodes=3

echo
echo "########### gcloud compute instances list - before after creation #############"
echo

gcloud compute instances list


echo
echo '############################################################################################'
echo "########### Start the point on the Cluster. Creating a GKE Deployment  ${GKE_DEPLOYMENT_NAME} ##############################"
echo '############################################################################################'
echo

kubectl run ${GKE_DEPLOYMENT_NAME} --image=${IMAGE_NAME}:${IMAGE_TAG} --port ${CONTAINER_PORT}

echo
echo "########### sleep for 2 minutes for nodes/apps start up  #############"
echo

sleep 120s 
#wait 90 sec


echo
echo "########### Expose application to traffic from the Internet  #############"
echo

# kubectl expose command creates a service resource, which provides networking and IP support to your application's Pods. 
# GKE creates an external IP and a Load Balancer for the  application.

kubectl expose deployment ${GKE_DEPLOYMENT_NAME} --type=LoadBalancer --port ${LOAD_BALANCER_PORT} --target-port ${CONTAINER_PORT}

sleep 60s 

echo
echo "########### Lists pods  #############"
echo

kubectl get pods

echo
echo "########### deployment details for ${GKE_DEPLOYMENT_NAME}  #############"
echo

kubectl get deployment ${GKE_DEPLOYMENT_NAME}

echo
echo "########### get external ip of the service  #############"
echo
EXTERNAL_IP=$(kubectl get svc ${GKE_DEPLOYMENT_NAME}   -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
sleep 3s
CURL_RESPONSE=$(curl ${EXTERNAL_IP}:${LOAD_BALANCER_PORT})
echo "Expected Message: ${MESSAGE}"
echo "Curl Response   : ${CURL_RESPONSE}"

if [ "${CURL_RESPONSE}" = "${MESSAGE}" ]
  then
    echo
    echo "############# Application is succesfully deployed GKE Cluster ####################"
  else
    echo
    echo "############# ERROR : application failed to deploy on GKE Cluster. Exiting deployment script #############" >&2
    exit 1
fi

echo
echo "########### scale deployment - increase replicas to 3  #############"
echo

kubectl scale deployment ${GKE_DEPLOYMENT_NAME} --replicas=3

echo
echo "########### deployment details for ${GKE_DEPLOYMENT_NAME} after scaling up #############"
echo

kubectl get deployment ${GKE_DEPLOYMENT_NAME}

echo

kubectl get pods

// deploy newer version
echo            
echo "########### use this command to deploy newer version of the image/application #############"
echo

#kubectl set image deployment/${GKE_DEPLOYMENT_NAME} ${GKE_DEPLOYMENT_NAME}=gcr.io/${PROJECT_ID}/hello-app:v2

echo            
echo "########### set autoscalling  #############"
echo


kubectl autoscale deployment ${GKE_DEPLOYMENT_NAME} --cpu-percent=80 --min=1 --max=5

echo
echo "########### delete GKE service ${GKE_DEPLOYMENT_NAME} #############"
echo

kubectl delete service ${GKE_DEPLOYMENT_NAME}
    
echo
echo "########### delete GKE deployment for ${GKE_DEPLOYMENT_NAME}  #############"
echo            

kubectl delete deployment ${GKE_DEPLOYMENT_NAME}


echo
echo "########### delete GKE cluster ${APP_NAME}-cluster  #############"
echo

gcloud container clusters delete ${APP_NAME}-cluster --quiet
                
                 
