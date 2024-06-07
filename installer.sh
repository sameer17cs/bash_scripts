#!/bin/bash

############################################################################################################################################
# @author: Sameer Deshmukh
# Purpose: This script automates deployment of certain tools using docker or apt packages
############################################################################################################################################

set -e

LIB_SCRIPT="_lib.sh"

docker_install() {
  echo "Installing Docker..."

  _prompt_for_input_ DOCKER_VERSION "Version to install (leave empty for the latest version)"

  sudo systemctl stop docker || true
  sleep 5

  sudo apt-get -y update
  sudo apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update -y

  if [ -z "$DOCKER_VERSION" ]; then
    echo "No version specified, installing the latest Docker version..."
    sudo apt-get -y install docker-ce docker-ce-cli containerd.io
  else
    echo -e "${C_BLUE}Installing Docker version $DOCKER_VERSION...${C_DEFAULT}"
    local available_versions=$(apt-cache madison docker-ce | awk '{print $3}')

    if echo "$available_versions" | grep -q "^$DOCKER_VERSION\$"; then
      sudo apt-get -y install docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io
    else
      echo -e "${C_RED}Specified Docker version $DOCKER_VERSION is not available.${C_DEFAULT}"
      echo -e "${C_PURPLE}Available versions are:\n$available_versions${C_DEFAULT}"
      exit 1
    fi
  fi

  sudo usermod -aG docker ${USER}
  sudo systemctl enable docker
  docker --version
}

docker_compose_install() {
  _prompt_for_input_ COMPOSE_VERSION "Docker Compose version to install (leave empty for the latest version)"

  if [ -z "$COMPOSE_VERSION" ]; then
    echo "No version specified, installing the latest Docker Compose version..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
  else
    echo "Installing Docker Compose version $COMPOSE_VERSION..."
    # Verify the provided version exists on GitHub
    if curl --output /dev/null --silent --head --fail "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)"; then
      COMPOSE_VERSION=$COMPOSE_VERSION
    else
      echo -e "${C_RED}Specified Docker Compose version $COMPOSE_VERSION is not available${C_DEFAULT}"
      exit 1
    fi
  fi

  sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  docker-compose --version
}

docker_registry() {

  _prompt_for_input_ DOCKER_SSL_DIR "Enter SSL certificate directory path" true
  echo "SSL directory is $DOCKER_SSL_DIR"

  # Create self-signed SSL certificate
  _prompt_for_input_ GENERATE_DRC "Generate SSL certificate (Y|y|N|n)"
  if [[ $GENERATE_DRC == "Y" || $GENERATE_DRC == "y" ]]; then
    openssl req -newkey rsa:4096 -nodes -sha256 -keyout $DOCKER_SSL_DIR/domain.key -x509 -days 365 -out $DOCKER_SSL_DIR/domain.crt
  fi
  
  # Run Docker registry container with SSL
  docker run -d \
    --restart always \
    --name registry \
    -v $DOCKER_SSL_DIR:/certs \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
    -p 5000:5000 \
    registry:2
}

purge_docker() {
  sudo systemctl stop docker || true
  sudo apt-get purge -y docker-engine docker docker.io docker-ce
  sudo apt-get autoremove -y --purge docker-engine docker docker.io docker-ce
  sudo rm -rf /var/lib/docker /etc/docker
  sudo rm /etc/apparmor.d/docker || true
  sudo rm -rf /var/run/docker.sock
  sudo apt autoremove -y
}

nginx() {
  #https://www.linuxcapable.com/how-to-install-nginx-mainline-on-ubuntu-22-04-lts/
  sudo add-apt-repository ppa:ondrej/nginx-mainline -y
  sudo apt update -y
  sudo apt install nginx -y
  sudo ufw allow 'Nginx Full'
  
  _prompt_for_input_ NGINX_CONFIG_PATH "custom configuration filepath (leave empty for default)"

  if [ -n "$NGINX_CONFIG_PATH" ] && [ -e "$NGINX_CONFIG_PATH" ]; then
    echo -e "${C_BLUE}copying configuration file from $NGINX_CONFIG_PATH${C_DEFAULT}"
    sudo mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bk
    sudo cp $NGINX_CONFIG_PATH /etc/nginx/sites-available/default
  else 
    echo "you choose to use default nginx config"
  fi

  sudo systemctl reload nginx
  sudo systemctl enable nginx
  sudo nginx -t
}

nginx_certbot() {
  _prompt_for_input_ NGINX_CONFIG_PATH "Nginx configuration filepath (leave empty for default)"

  if [ -n "$NGINX_CONFIG_PATH" ] && [ -e "$NGINX_CONFIG_PATH" ]; then
    echo -e "${C_BLUE}copying configuration file from $NGINX_CONFIG_PATH${C_DEFAULT}"
    sudo mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bk
    sudo cp $NGINX_CONFIG_PATH /etc/nginx/sites-available/default
  else
    echo "You chose to use the default Nginx config"
  fi

  # Initialize an array to hold domain names
  DOMAIN_NAMES=()

  # Loop to collect multiple domain names
  while true; do
    _prompt_for_input_ NGINX_DOMAIN "Enter Domain name (leave empty to finish)"
    
    if [ -z "$NGINX_DOMAIN" ]; then
      break
    fi

    DOMAIN_NAMES+=($NGINX_DOMAIN)
  done

  if [ ${#DOMAIN_NAMES[@]} -eq 0 ]; then
    echo -e "${C_RED}No domain names provided${C_DEFAULT}"
    exit 1
  fi

  sudo apt install certbot python3-certbot-nginx -y || true

  # Prepare the domain arguments for certbot
  DOMAIN_ARGS=""
  for DOMAIN in "${DOMAIN_NAMES[@]}"; do
    DOMAIN_ARGS="$DOMAIN_ARGS -d $DOMAIN -d www.$DOMAIN"
  done

  # Run certbot with the collected domain names
  sudo certbot --nginx $DOMAIN_ARGS
  sudo service nginx restart
}

mongodb () {

  local container_name="mongodb"

  _prompt_for_input_ DATADIR "Enter MongoDB data directory full path" true
  ensure_directory_exists "$DATADIR"

  docker run --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  --volume $DATADIR:/data/db \
  -p 27017:27017 \
  --name $container_name mongo --quiet

  MONGODB_VERSION=$(docker exec $container_name mongod --version | awk '/version/ {print $3}')
  echo -e "${C_BLUE}Mongodb version $MONGODB_VERSION${C_DEFAULT}"
}

mysql() {
  local container_name="mysql"

  _prompt_for_input_ MYSQL_DATADIR "Enter MySQL data directory full path" true
  ensure_directory_exists "$DATADIR"

  docker run -d \
    --name $container_name \
    -e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
    -v $MYSQL_DATADIR:/var/lib/mysql \
    -p 3306:3306 \
    mysql:latest

  MYSQL_VERSION=$(docker exec $container_name mysql --version | grep -oP '(?<=Ver\s)[^ ]+')
  echo -e "${C_BLUE}MySQL version $MYSQL_VERSION${C_DEFAULT}"
}

redis () {

  local container_name="redis"
  
  _prompt_for_input_ DATADIR "Enter Redis data directory full path" true
  ensure_directory_exists "$DATADIR"

  docker run  --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  --volume $DATADIR:/data \
  -p 6379:6379 \
  --name $container_name redis --appendonly yes

  #set defaults
  #docker exec $container_name bash -c 'apt update && apt install -y procps && echo "vm.overcommit_memory=1" >> /etc/sysctl.conf && sysctl -p'

  REDIS_VERSION=$(docker exec $container_name redis-server --version | awk '{print $3}' | cut -d= -f2)
  echo -e "${C_BLUE}Redis version: $REDIS_VERSION${C_DEFAULT}"
}

elasticsearch() {

  local container_name="elasticsearch"
  local default_version="8.14.0"
  local username="elastic"

  _prompt_for_input_ VERSION "Enter Elasticsearch version (default: 8.14.0)" false
  
  _prompt_for_input_ DATADIR "Enter Elasticsearch data directory full path" true
  ensure_directory_exists $DATADIR
  
  _prompt_for_input_ PWD "Enter password for the Elasticsearch root user (username: $username)" true
  
  _prompt_for_input_ ELASTIC_MIN_MEMORY "Enter minimum memory (MB) for Elasticsearch" true
  _prompt_for_input_ ELASTIC_MAX_MEMORY "Enter maximum memory (MB) for Elasticsearch" true

  docker run --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  -p 9200:9200 -p 9300:9300 \
  --volume $DATADIR:/usr/share/elasticsearch/data \
  --env "bootstrap.memory_lock=true" \
  --env "discovery.type=single-node" \
  --env "ELASTIC_PASSWORD=$PWD" \
  --env "xpack.security.enabled=true" \
  --env "ES_JAVA_OPTS=-Xms${ELASTIC_MIN_MEMORY}m -Xmx${ELASTIC_MAX_MEMORY}m" \
  --ulimit memlock=-1:-1 \
  --name $container_name docker.elastic.co/elasticsearch/elasticsearch:${VERSION:-$default_version}

  # Wait for Elasticsearch to be ready
  echo "Waiting for Elasticsearch to be available..."
  until curl -s -o /dev/null -w "%{http_code}" -u elastic:$PWD http://127.0.0.1:9200 | grep -q "200"; do
    echo "Elasticsearch is not ready yet. Retrying in 30 seconds..."
    sleep 30
  done

  echo -e "${C_GREEN}Elasticsearch setup complete.${C_DEFAULT}"
  echo -e "${C_BLUE}Elasticsearch username: $username${C_DEFAULT}"
  echo -e "${C_BLUE}Elasticsearch password: $PWD${C_DEFAULT}"
}

kibana() {
  local container_name="kibana"
  local default_elastic_host="http://127.0.0.1:9200"
  local default_kibana_version="8.14.0"

  _prompt_for_input_ ELASTIC_HOST "Enter Elasticsearch host URL (default: $default_elastic_host)" false
  ELASTIC_HOST="${ELASTIC_HOST:-$default_elastic_host}"

  _prompt_for_input_ KIBANA_VERSION "Enter Kibana version (default: $default_kibana_version)" false

  local kibana_system_user="kibana_system"
  local kibana_system_password=$(openssl rand -base64 12)
  local temp_file="/tmp/response.json"

  echo -e "${C_GREEN}Setting up password for Elasticsearch user '${kibana_system_user}'...${C_DEFAULT}"

  # Get Elasticsearch root user password
  while true; do
    _prompt_for_input_ "ELASTIC_ROOT_PASSWORD" "Enter password for the Elasticsearch root user (elastic)" true

    # Test the root user password
    if curl -s -o /dev/null -w "%{http_code}" -u "elastic:$ELASTIC_ROOT_PASSWORD" "$ELASTIC_HOST" | grep -q "200"; then
      break
    else
      echo -e "${C_RED}Invalid Elasticsearch root user password. Please try again...${C_DEFAULT}"
      echo
    fi
  done

  # Update password for kibana_system user
  payload="{\"password\":\"$kibana_system_password\"}"
  response=$(curl -s -w "%{http_code}" -o $temp_file -X POST "$ELASTIC_HOST/_security/user/$kibana_system_user/_password" -H "Content-Type: application/json" -u "elastic:$ELASTIC_ROOT_PASSWORD" -d "$payload")
  if [[ "$response" == "200" ]]; then
    echo -e "${C_BLUE}Password for user '$kibana_system_user' updated successfully.${C_DEFAULT}"
  else
    echo -e "${C_RED}Failed to update password for user '$kibana_system_user'. Response:${C_DEFAULT}"
    cat $temp_file
    echo
    rm $temp_file
    return 1
  fi

  rm $temp_file

  # Data directory for Kibana
  _prompt_for_input_ DATADIR "Enter Kibana data directory full path" true
  ensure_directory_exists "$DATADIR"

  # Create Kibana container
  docker run --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  --network host \
  -p 5601:5601 \
  --volume $DATADIR:/usr/share/kibana/data \
  --env "ELASTICSEARCH_HOSTS=$ELASTIC_HOST" \
  --env "ELASTICSEARCH_USERNAME=$kibana_system_user" \
  --env "ELASTICSEARCH_PASSWORD=$kibana_system_password" \
  --env "XPACK_SECURITY_ENABLED=true" \
  --env "XPACK_SECURITY_SESSION_IDLETIMEOUT=1h" \
  --env "XPACK_SECURITY_SESSION_LIFETIME=24h" \
  --name $container_name docker.elastic.co/kibana/kibana:${KIBANA_VERSION:-$default_kibana_version}

  echo -e "${C_GREEN}Kibana setup complete, use elastic username and password to login ${C_DEFAULT}"
}

neo4j () {

  local username="neo4j"
  local container_name="neo4j"

  _prompt_for_input_ DATADIR "Enter neo4j data directory full path" true
  ensure_directory_exists "$DATADIR"

  _prompt_for_input_ PWD "Enter password for user $username" true

  _prompt_for_input_ MAX_MEMORY "Enter max memory in gb" true

  docker run --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  --volume $DATADIR/data:/data \
  --volume $DATADIR/logs:/logs \
  --volume $DATADIR/import:/var/lib/neo4j/import \
  --volume $DATADIR/plugins:/var/lib/neo4j/plugins \
  -p 7474:7474 -p 7687:7687 \
  --env NEO4J_AUTH=$username/$PWD \
  --env NEO4J_apoc_import_file_enabled=true \
  --env NEO4J_dbms_memory_transaction_total_max=$MAX_MEMORY \
  --name $container_name neo4j:latest

  _prompt_for_input_ LOAD_PLUGIN "Load default plugins (Y|y|N|n) (default: N)"

  if [[ $LOAD_PLUGIN == "Y" || $LOAD_PLUGIN == "y" ]]; then
    ##copy default plugins
    docker exec $container_name sh -c "cp /var/lib/neo4j/labs/*.jar /var/lib/neo4j/plugins/"
    sleep 5
    docker restart $container_name
  fi
  local version=$(docker exec $container_name neo4j-admin version | grep -oP '\d+\.\d+(\.\d+)*')
  echo -e "${C_GREEN}Neo4j version $NEO4J_VERSION${C_DEFAULT}"
  echo -e "${C_BLUE} Username: $username, Password: $PWD${C_DEFAULT}"
}

redash() {
  local compose_file="docker_compose/redash.yml"

  _prompt_for_input_ DATADIR "Enter the base data directory for Redash" true
  ensure_directory_exists "$DATADIR"

  # Set environment variables
  export POSTGRES_DATADIR="${DATADIR}/postgres"
  export REDIS_DATADIR="${DATADIR}/redis"

  ensure_directory_exists "$POSTGRES_DATADIR"
  ensure_directory_exists "$REDIS_DATADIR"

  _prompt_for_input_ CREATE_DB "Create DBs (Y|y|N|n) (default: N)"
  if [[ $CREATE_DB == "Y" || $CREATE_DB == "y" ]]; then
     docker-compose -f $compose_file run --rm redash create_db
     sleep 5
  fi
  
  docker-compose -f $COMPOSE_FILE up -d

  REDASH_VERSION=$(docker exec -it $DOCKER_CONTAINER_NAME redash version)
  echo -e "${C_GREEN}Redash version $REDASH_VERSION${C_DEFAULT}"

}

metabase () {

  local container_name="metabase"

  _prompt_for_input_ DATADIR "Enter metabase data directory full path" true
  ensure_directory_exists "$DATADIR"

  docker run --detach --log-opt max-size=50m --log-opt max-file=5 --restart unless-stopped \
  --volume $DATADIR:/metabase-data \
  --env MB_DB_FILE=/metabase-data/metabase.db \
  --env MB_DB_TYPE=h2 \
  -p 5000:3000 \
  --name $container_name metabase/metabase

  METABASE_VERSION=$(docker exec $container_name /app/bin/run_metabase.sh version)
  echo -e "${C_GREEN}Metabase version $METABASE_VERSION${C_DEFAULT}"
}

ensure_directory_exists() {
  local dir_path="$1"
  if [ ! -d "$dir_path" ]; then
    mkdir -p "$dir_path"
    if [ $? -eq 0 ]; then
      echo -e "${C_GREEN}Directory $dir_path created successfully.${C_DEFAULT}"
    else
      echo -e "${C_RED}Failed to create directory $dir_path. Exiting...${C_DEFAULT}"
      exit 1
    fi
  fi
}

main() {

  local option_selected=$1

  source $LIB_SCRIPT

  declare -a FUNCTIONS=(
    docker_install
    docker_compose_install
    docker_registry
    purge_docker
    nginx
    nginx_certbot
    mongodb
    mysql
    redis
    elasticsearch
    kibana
    neo4j
    redash
    metabase
  )

  # Check if function exists & run it, otherwise list options
  if [[ " ${FUNCTIONS[@]} " =~ " $option_selected " ]]; then
    echo "---------------------------------------------------"
    echo -e "\033[0;32m Option selected: $option_selected \033[0m"
    echo "---------------------------------------------------"
    
    #call the function
    "$option_selected"
  else
    echo -e "${C_RED}Unknown option $option_selected, please choose from below options${C_DEFAULT}"
    _print_array_ "${FUNCTIONS[@]}"
  fi
}

main $1