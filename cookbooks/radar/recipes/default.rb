# Author: Leonardo Leite (2014)
# License: GPL v3
# Receita de instalação do Radar Parlamentar

user = node['radar']['user']
home = node['radar']['home_user']
radar_folder = "#{home}/radar"
repo_folder = "#{home}/repo"
venv_folder = "#{home}/venv_radar"
cache_folder = "/tmp/django_cache"
log_folder = "/var/log/radar"
log_file = "#{log_folder}/radar.log"
uwsgi_log_folder = "/var/log/"
uwsgi_log_file = "/var/log/uwsgi.log"
script_folder = "#{radar_folder}/scripts"
cron_folder = "#{repo_folder}/radar_parlamentar/cron"
dump_file = "#{repo_folder}/radar_parlamentar/static/db-dump/radar.sql"


elasticsearch_user 'radar'


elasticsearch_install 'elasticsearch' do
  type :package
  action :install
end

elasticsearch_configure 'elasticsearch' do
  allocated_memory '256m'
  configuration ({
    'cluster.name' => 'mycluster',
    'node.name' => 'node01'
  })
end


elasticsearch_service 'elasticsearch' do
  service_actions [:enable, :start]
end

#
# Adicionando repositórios externos necessários
#

apt_repository 'java' do
  uri          'ppa:webupd8team/java'
  distribution node['lsb']['codename']
end

#
# Instalando pacotes
#

package "libshadow-ruby1.8" do
  action :install
end

package "python-pip" do
  action :install
end

package "python-dev" do
  action :install
end

package "git" do
  action :install
end

package "python-virtualenv" do
  action :install
end

# package "tmux" do
#   action :install
# end

package "postgresql-9.1" do
  action :install
end

package "uwsgi-plugin-python" do
  action :install
end

package "vim" do
  action :install
end

package "curl" do
  action :install
end

package "openjdk-7-jdk" do
  action :install
end


#
# Cria usuario radar
#
user 'radar' do
  supports :manage_home => true
  comment 'User Radar'
  home '/home/radar'
  shell '/bin/bash'
  password '$1$mkzBgh6.$uMYniXncsQvGI85us6PH/1'
  system true
end

#
# Instala e configura Postgresql como a base de dados "radar"
#

include_recipe "database::postgresql"

template "#{home}/.pgpass" do
  mode '0600'
  owner user
  group user
  source "pgpass.erb"
  variables({
    :senha => node['radar']['database_password']
  })
end

file '/root/.pgpass' do
  content 'localhost:5432:postgres:postgres:postgres'
  action :create
  mode '0600'
end


bash 'set_password_for_postgres' do
  code <<-EOH
  sudo -u postgres psql postgres -c "ALTER USER postgres WITH PASSWORD 'postgres';"
  EOH
  not_if 'psql -h localhost -U postgres -c "SELECT 1"', :cwd => '/root'
end

# create connection info as an external ruby hash
postgresql_connection_info = {:host => "127.0.0.1",
                              :port => node['postgresql']['config']['port'],
                              :username => 'postgres',
                              :password => node['postgresql']['password']['postgres']}

# create a postgresql user but grant no privileges
postgresql_database_user 'radar' do
  connection postgresql_connection_info
  password node['radar']['database_password']
  action :create
end


# create a radar database with additional parameters
postgresql_database 'radar' do
  connection postgresql_connection_info

  template 'DEFAULT'
  database_name 'radar'
  encoding 'DEFAULT'
  tablespace 'DEFAULT'
  connection_limit '-1'
  owner 'radar'
  action :create
end

# grant all privileges on all tables in radar db
postgresql_database_user 'radar' do
  connection(
    :host     => '127.0.0.1',
    :port     => 5432,
    :username => 'radar',
    :password => node['radar']['database_password']
  )
  privileges [:all]
  action :grant
  database_name 'radar'
end



#
# Variáveis de ambiente
#

template "#{home}/.profile" do
  mode '0440'
  owner user
  group user
  source "profile.erb"
  variables({
    :django_home => "#{repo_folder}/radar_parlamentar",
    :script_folder => script_folder,
    :venv_folder => venv_folder
  })
end

#
# Código e configuração do Radar
#

directory "#{radar_folder}" do
  owner user
  group user
  mode '0775'
  action :create
end

python_virtualenv "#{venv_folder}" do
  owner node['radar']['user']
  group user
  action :create
  options "--setuptools"
end

git "#{repo_folder}" do
  repository "https://github.com/radar-parlamentar/radar.git"
  reference "master"
  user user
  group user
  action :sync
end

python_pip "" do
  virtualenv "#{venv_folder}"
  options "-r #{repo_folder}/radar_parlamentar/requirements.txt"
end

directory "#{cache_folder}" do
  owner user
  group user
  mode '666'
  action :create
end

template "#{repo_folder}/radar_parlamentar/settings/production.py" do
  mode '0440'
  owner user
  group user
  source "production.py.erb"
  variables({
    :dbname => 'radar',
    :dbuser => 'radar',
    :dbpassword => node['radar']['database_password'],
    :cache_folder => cache_folder,
    :log_file => log_file
  })
end

directory log_folder do
  owner user
  group user
  mode '0755'
  action :create
end

file log_file do
  owner user
  group user
  mode '0755'
  action :create
end

execute "syncdb" do
  command "#{venv_folder}/bin/python manage.py syncdb --noinput"
  environment ({"DJANGO_SETTINGS_MODULE" => "settings.production"})
  cwd "#{repo_folder}/radar_parlamentar"
  user user
  group user
  action :run
end

execute "migrate" do
  command "#{venv_folder}/bin/python manage.py migrate"
  environment ({"DJANGO_SETTINGS_MODULE" => "settings.production"})
  cwd "#{repo_folder}/radar_parlamentar"
  user user
  group user
  action :run
end

#
# Uwsgi
#

template "#{radar_folder}/radar_uwsgi.ini" do
  mode '0440'
  owner user
  group user
  source "radar_uwsgi.ini.erb"
  variables({
    :user => user
  })
end

template "#{radar_folder}/uwsgi_params" do
  mode '0440'
  owner user
  group user
  source "uwsgi_params.erb"
end

# python_pip "uwsgi" do
# end

directory uwsgi_log_folder do
  owner user
  group user
  mode '0755'
  action :create
end

template "/etc/init/uwsgi.conf" do
  mode '777'
  owner 'root'
  group 'root'
  source "uwsgi.conf.erb"
  variables({
    :uwsgi_log_file => uwsgi_log_file,
    :radar_folder => radar_folder
  })
end

service "uwsgi" do
  provider Chef::Provider::Service::Upstart
  action :reload
end

#
# Nginx
#

package "nginx" do
  action :install
end

template "#{radar_folder}/radar_nginx.conf" do
  mode '0440'
  owner user
  group user
  source "radar_nginx.conf.erb"
  variables({
    :user => user,
    :server_name => "localhost"
  })
end

link "/etc/nginx/sites-enabled/radar_nginx.conf" do
  to "#{home}/radar/radar_nginx.conf"
end

file "/etc/nginx/sites-enabled/default" do
  action :delete
end

service "nginx" do
  action :restart
end

#
# Celery
#

package "rabbitmq-server" do
  action :install
end

template "/etc/default/celeryd" do
  mode '0444'
  owner 'root'
  group 'root'
  source "celeryd.conf.erb"
  variables({
    :repo_folder => repo_folder,
    :venv_folder => venv_folder,
    :user => user
  })
end

template "/etc/init.d/celeryd" do
  mode '0777'
  owner 'root'
  group 'root'
  source "celeryd.erb"
end

service "celeryd" do
  action :start
end


# Criar usuario para administrativo do Django (usado na importação dos dados via requisição web)

template "#{repo_folder}/radar_parlamentar/create_user.py" do
  mode '777'
  owner user
  group user
  source "create_user.py.erb"
  variables({
    :user => 'radar',
    :password => node['radar']['database_user_password']
  })
end

execute "create_user" do
  command "#{venv_folder}/bin/python create_user.py"
  environment ({"DJANGO_SETTINGS_MODULE" => "settings.production"})
  cwd "#{repo_folder}/radar_parlamentar/"
  user user
  group user
  action :run
end

file "#{repo_folder}/radar_parlamentar/create_user.py" do
  action :delete
end

#
# Importaçao de dados
#

directory "#{script_folder}" do
  owner user
  group user
  mode '0775'
  action :create
end

template "#{script_folder}/importar_dados.sh" do
  mode '777'
  owner user
  group user
  source "importar_dados.sh.erb"
  variables({
    :user => 'radar',
    :password => node['radar']['database_user_password'],
    :server_user => node['radar']['user']
  })
end

execute "importar_dados" do
  command "sh importar_dados.sh"
  cwd "#{script_folder}"
  user user
  group user
  action :run
end

#
# Rotinas periódicas do Radar
#

cron "cache-analises" do
  action :create
  minute '0'
  hour '1'
  shell '/bin/bash'
  user user
  command "{ $SHELL #{cron_folder}/clear-cache.sh && $SHELL #{cron_folder}/cache-analises.sh; } >> #{log_folder}/radar-cron.log 2>&1"
end

cron "dump-db" do
  action :create
  minute '0'
  hour '4'
  weekday '1'
  shell '/bin/bash'
  user user
  command "#{cron_folder}/dump-radar.sh #{dump_file} >> #{log_folder}/radar-cron.log 2>&1"
end
