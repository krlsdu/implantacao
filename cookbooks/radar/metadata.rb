name 'radar'
maintainer       "Radar Parlamentar"
maintainer_email "radarparlamentar@polignu.org"
license          "GPL v3"
description      "Installs Radar Parlamentar"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.0.1"

# depends "postgresql"
depends "database"
depends "python"
depends "jenkins"
depends "sonarqube"
depends "java"
depends "elasticsearch"
