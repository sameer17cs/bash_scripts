##Author: Sameer Deshmukh
#!/bin/bash
set -e
APP=$1

print_app_options () {
  echo " Valid options are:
       1) install_docker
       2) install_compose
       3) purge_stack
       4) purge_docker
       "
}

install_docker() {
  echo "installing docker .."
  sudo systemctl stop docker || true
  sleep 5
  sudo apt-get -y update
  sudo apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update -y
  sudo apt-cache policy docker-ce
  sudo apt install docker-ce -y
  sudo usermod -aG docker ${USER}
  sudo systemctl enable docker
  docker --version
}

install_docker_compose() {
  COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
  sudo curl -L https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  docker-compose --version
}

purge_stack() {
  read -p "Enter docker stack to be purged " stackname
  echo "clean existing docker stack $stackname"
  docker stack rm $stackname || true
  docker stop -t 30 $(docker ps -a -q) || true
  docker rm -v $(docker ps -a -q) --force || true
  docker volume prune --force || true
  docker rmi $(docker images -a -q) --force || true
  docker system prune -a --force
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

main () {
  if [ -z "$APP" ]; then
    echo "App type not selected"
    print_app_options
    exit 1
  fi  

  case $APP in
    install_docker)
      echo "Running docker install commands"
      install_docker
      ;;

    install_docker_compose)
      echo "Running docker compose install commands"
      install_docker_compose
      ;;

    purge_stack)
      echo "Running stack purge commands"
      purge_stack
      ;;

    purge_docker)
      echo "Running docker purge commands"
      purge_docker
      ;;

    *)
      echo "Unknown application: $APP"
      print_app_options
      ;;
  esac
}

main