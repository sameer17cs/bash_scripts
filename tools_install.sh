#!/bin/bash

############################################################################################################################################
# @author: Sameer Deshmukh
# Purpose: This script automates deployment of certain tools.
#        - nginx using apt
#        - nginx certbot using apt
#        - mongodb using docker
#        - redis using docker
#        - elasticsearch using docker
#        - neo4j using docker
############################################################################################################################################

set -e
APP=$1

print_app_options () {
  echo " Valid options are:
       1) nginx
       2) nginx_certbot
       3) mongodb
       4) redis
       5) elasticsearch
       6) neo4j
       7) redash
       8) metabase
       "
}

setup_nginx() {
  #https://www.linuxcapable.com/how-to-install-nginx-mainline-on-ubuntu-22-04-lts/
  sudo add-apt-repository ppa:ondrej/nginx-mainline -y
  sudo apt update -y
  sudo apt install nginx -y
  sudo ufw allow 'Nginx Full'
  
  read -p "---- If you want to use custom configuration file, provide filepath (leave empty for default) ----" : nginx_config_loc

  if [ -n "$nginx_config_loc" && -e "$nginx_config_loc" ]; then
    sudo mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bk
    sudo cp $nginx_config_loc /etc/nginx/sites-available/default
  fi

  sudo systemctl reload nginx
  sudo systemctl enable nginx
  sudo nginx -t
}

setup_nginx_certbot() {

  #read input
  read -p "---- If you want to use custom configuration file, provide filepath (leave empty for default) ----" : nginx_config_loc

  if [ -n "$nginx_config_loc" && -e "$nginx_config_loc" ]; then
    sudo mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bk
    sudo cp $nginx_config_loc /etc/nginx/sites-available/default
  fi

  read -p "Enter Domain name: " domain_name
  if [ -z "$domain_name" ]; then
    echo "Invalid domain name"
    exit 1
  fi

  sudo apt install certbot python3-certbot-nginx -y || true
  sudo certbot --nginx -d $domain_name -d www.$domain_name
  sudo service nginx restart
}

setup_mongodb () {

  MONGO_CONTAINER_NAME="my_mongo_server"

  read -p "Enter mongodb data directory full path: " mongodb_datadir
  if [ -z "$mongodb_datadir" ]; then
    echo "Invalid directory"
    exit 1
  fi

  docker run --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  --volume $mongodb_datadir:/data/db \
  -p 27017:27017 \
  --name $MONGO_CONTAINER_NAME mongo --quiet

 MONGODB_VERSION=$(docker exec $MONGO_CONTAINER_NAME mongod --version | grep -Po '"version": "\K[^"]+')
 echo "Mongodb version $MONGODB_VERSION"
}

setup_redis () {

  REDIS_CONTAINER_NAME="my_redis_server"
  
  read -p "Enter redis data directory full path: " redis_datadir
  if [ -z "$redis_datadir" ]; then
    echo "Invalid directory"
    exit 1
  fi

  docker run  --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  --volume $redis_datadir:/data \
  -p 6379:6379 \
  --name $REDIS_CONTAINER_NAME redis --appendonly yes

  #set defaults
  #docker exec $REDIS_CONTAINER_NAME bash -c 'apt update && apt install -y procps && echo "vm.overcommit_memory=1" >> /etc/sysctl.conf && sysctl -p'

  REDIS_VERSION=$(docker exec $REDIS_CONTAINER_NAME redis-server --version | awk '{print $3}' | cut -d= -f2)
  echo "Redis version: $REDIS_VERSION"
}

setup_elasticsearch () {
  echo "Not implemented"
}

setup_neo4j () {

  AUTH_USERNAME="neo4j"
  AUTH_PASSWORD="password"
  DOCKER_CONTAINER_NAME="my_neo4j_server"
  PLUGINS_DOWNLOAD_DIR="/tmp/neo4j_plugins"
  MAX_MEMORY_TRASACTION="8g"

  read -p "Enter neo4j data directory full path: " neo4j_datadir
  if [ -z "$neo4j_datadir" ]; then
    echo "Invalid directory"
    exit 1
  fi

  read -p "Enter neo4j auth password (default: $AUTH_PASSWORD ): " neo4j_auth_password
  if [ ! -z "$neo4j_auth_password" ]; then
    AUTH_PASSWORD=$neo4j_auth_password
  fi
  echo "Auth username: $AUTH_USERNAME, Auth password: $AUTH_PASSWORD"

  docker run --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  --volume $neo4j_datadir/data:/data \
  --volume $neo4j_datadir/logs:/logs \
  --volume $neo4j_datadir/import:/var/lib/neo4j/import \
  --volume $neo4j_datadir/plugins:/var/lib/neo4j/plugins \
  -p 7474:7474 -p 7687:7687 \
  --env NEO4J_AUTH=$AUTH_USERNAME/$AUTH_PASSWORD \
  --env NEO4J_apoc_import_file_enabled=true \
  --env NEO4J_dbms_memory_transaction_total_max=$MAX_MEMORY_TRASACTION \
  --name $DOCKER_CONTAINER_NAME neo4j:latest

  NEO4J_VERSION=$(docker exec $DOCKER_CONTAINER_NAME neo4j-admin version | grep -oP '\d+\.\d+(\.\d+)*')

  read -p "Load default plugins (Y|y|N|n)  (default: N) : " load_default_plugins
  if [[ $load_default_plugins == "Y" || $load_default_plugins == "y" ]]; then
    ##copy default plugins
    docker exec $DOCKER_CONTAINER_NAME sh -c "cp /var/lib/neo4j/labs/*.jar /var/lib/neo4j/plugins/"
    sleep 5
    docker restart $DOCKER_CONTAINER_NAME
  fi
  echo "Neo4j version $NEO4J_VERSION"
}

setup_redash () {

  DOCKER_CONTAINER_NAME="my_redash_server"
  COMPOSE_FILE="docker_compose/redash_prod.yml"

  #first docker compose up
  read -p "Enter postgres data directory full path: " postgres_datadir
  if [ -z "$postgres_datadir" ]; then
    echo "Invalid directory"
    exit 1
  fi

  read -p "Enter redis data directory full path: " redis_datadir
  if [ -z "$redis_datadir" ]; then
    echo "Invalid directory"
    exit 1
  fi

  #edit compose file
  rm $COMPOSE_FILE || true
  cp docker_compose/redash.yml $COMPOSE_FILE
  sed -i "s#<replace_with_path_to_postgres_data>#$postgres_datadir#g" $COMPOSE_FILE
  sed -i "s#<replace_with_path_to_redis_data>#$redis_datadir#g" $COMPOSE_FILE
  sed -i "s#<replace_with_redash_container_name>#$DOCKER_CONTAINER_NAME#g" $COMPOSE_FILE

  read -p "Create dbs (Y|y|N|n)  (default: N) : " create_dbs
  if [[ $create_dbs == "Y" || $create_dbs == "y" ]]; then
     docker-compose -f $COMPOSE_FILE run --rm redash create_db
     sleep 5
  fi
  
  docker-compose -f $COMPOSE_FILE up -d

  REDASH_VERSION=$(docker exec -it $DOCKER_CONTAINER_NAME redash version)
  echo "Redash version $REDASH_VERSION"
}

setup_metabase () {

  DOCKER_CONTAINER_NAME="my_metabase_server"

  read -p "Enter metabase data directory full path: " metabase_datadir
  if [ -z "$metabase_datadir" ]; then
    echo "Invalid directory"
    exit 1
  fi

  docker run --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  --volume $metabase_datadir:/metabase-data \
  -e MB_DB_FILE=/metabase-data/metabase.db \
  -e MB_DB_TYPE=h2 \
  -p 5000:3000 \
  --name $DOCKER_CONTAINER_NAME metabase/metabase

  METABASE_VERSION=$(docker exec $DOCKER_CONTAINER_NAME /app/bin/run_metabase.sh version)
  echo "Metabase version $METABASE_VERSION"
}

main () {
  if [ -z "$APP" ]; then
    echo "App type not selected"
    print_app_options
    exit 1
  fi  

  case $APP in
    nginx)
      echo "Installing nginx"
      setup_nginx
      ;;

    nginx_certbot)
      echo "Installing certbot"
      setup_nginx_certbot
      ;;

    mongodb)
      echo "Setting up monogdb on docker"
      setup_mongodb
      ;;

    redis)
      echo "Setting up redis on docker"
      setup_redis
      ;;

    elasticsearch)
      echo "Setting up elasticsearch on docker"
      setup_elasticsearch
      ;;

    neo4j)
      echo "Setting up neo4j on docker"
      setup_neo4j
      ;;

    redash)
      echo "Setting up redash on docker-compose"
      setup_redash
      ;;

    metabase)
      echo "Setting up metabase on docker"
      setup_metabase
      ;;

    *)
      echo "Unknown application: $APP"
      print_app_options
      ;;
  esac
}

main