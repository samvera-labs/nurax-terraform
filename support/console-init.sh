#!/bin/bash -ex
if [[ ! -e /home/admin/.init-complete ]]; then
  exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

  mkdir -p /mnt/stack-data /mnt/nurax-data
  cat >> /etc/fstab <<'EOF'
${stack_efs_id}:/ /mnt/stack-data efs _netdev,noresvport,tls,iam 0 0
${nurax_efs_id}:/ /mnt/nurax-data efs _netdev,noresvport,tls,iam 0 0
EOF

  cat > install_keys.sh <<'EOF'
mkdir -p /home/admin/.ssh
for u in ${console_users}; do 
  curl https://github.com/$u.keys >> /home/admin/.ssh/authorized_keys
done
chmod -R go-rwx /home/admin/.ssh
EOF

  chmod 0755 install_keys.sh
  sudo -u admin install_keys.sh
  rm install_keys.sh

  # Install EFS Utils, SSM Agent, and Session Manager 
  cd /tmp

  git clone https://github.com/aws/efs-utils
  cd efs-utils
  ./build-deb.sh 
  apt-get -y install ./build/amazon-efs-utils*deb
  cd ..
  rm -rf efs-utils

  curl -o amazon-ssm-agent.deb https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
  dpkg -i amazon-ssm-agent.deb
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent

  curl -o session-manager-plugin.deb https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb
  dpkg -i session-manager-plugin.deb
  systemctl enable session-manager-plugin
  systemctl start session-manager-plugin

  rm amazon-ssm-agent.deb session-manager-plugin.deb

  # Install required packages
  curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
  curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
  echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

  apt-get install --no-install-recommends --fix-missing --allow-unauthenticated -y \
    ca-certificates ruby-dev nodejs yarn build-essential libpq-dev libreoffice imagemagick \
    git unzip ghostscript vim ffmpeg clamav-freshclam clamav-daemon libclamav-dev jq \
    libqt5webkit5-dev xvfb xauth default-jre-headless docker.io unzip postgresql-client libpq-dev

  usermod -a -G docker admin
  gem install --no-doc --no-ri bundler

  # Install AWS CLI v2
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "mp/awscliv2.zip"
  unzip -qo awscliv2.zip -d /tmp
  aws/install
  rm -rf aws awscliv2.zip

  # Install FITS
  mkdir -p /opt/fits && \
    curl -fSL -o /opt/fits/fits-1.5.0.zip https://github.com/harvard-lts/fits/releases/download/1.5.0/fits-1.5.0.zip && \
    cd /opt/fits && unzip fits-1.5.0.zip && chmod +X fits.sh && rm fits-1.5.0.zip

  touch /home/admin/.init-complete
fi
--//--
