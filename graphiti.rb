require 'rubygems'
require 'bundler'
Bundler.setup

if !defined?(RACK_ENV)
  RACK_ENV = ENV['RACK_ENV'] || 'development'
end

require 'sinatra/base'
require 'sinatra/contrib'
require 'sinatra_auth_github'
require 'redis/namespace'
require 'compass'
require 'typhoeus'
require 'yajl'
require 'redised'
require 'digest/sha1'

require './lib/s3/request'
require './lib/s3/signature'

require './lib/metric'
require './lib/graph'
require './lib/dashboard'

class Graphiti < Sinatra::Base

  VERSION = '0.2.0'

  register Sinatra::Contrib

  config_file 'config/settings.yml'

  configure do
    set :logging, true
    Compass.configuration do |config|
      config.project_path = settings.root
      config.sass_dir = File.join(settings.views, 'stylesheets')
      config.output_style = :compact
    end
    set :haml, :format => :html5
    set :scss, Compass.sass_engine_options
    set :method_override, true
    set :protection, :except => :json_csrf
    Graph.redis = settings.redis_url
    Dashboard.redis = settings.redis_url
    Metric.redis = settings.redis_url
  end

  if settings.use_github_oauth == true 
    set :github_options, {
      :scopes       => settings.github_scope,
      :secret       => settings.github_client_secret,
      :client_id    => settings.github_client_id,
      :callback_url => settings.github_callback_url
    }
  end

  enable :sessions
  set    :session_secret, settings.auth_token

  register Sinatra::Auth::Github

  before do
    S3::Request.logger = logger
    login
  end

  helpers do
    def base_url
      @base_url ||= "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
    end
  end

  if settings.use_github_oauth == true 
    def login
      authenticate!
      if github_organization_authenticate!(settings.github_org_id)
        user = github_user.name
        @current_user = session[:user] = user
      else
        session.clear
        redirect '/403.html'
      end
    end

    get '/unauthenticated' do
      if session[:user].nil?
        redirect '/'
      else
        session.clear
        redirect '/403.html'
      end
    end

    get '/logout' do
      logout!
      redirect settings.return_url
    end
  end
  
  get '/graphs/:uuid.js' do
    json Graph.find(params[:uuid])
  end

  get '/metrics.js' do
    json :metrics => Metric.find(params[:q])
  end

  get '/graphs.js' do
    json :graphs => Graph.all
  end

  get '/dashboards/:slug.js' do
    json Dashboard.find(params[:slug], true)
  end

  get '/dashboards.js' do
    if params[:uuid]
      json :dashboards => Dashboard.without_graph(params[:uuid])
    else
      json :dashboards => Dashboard.all
    end
  end

  post '/graphs' do
    uuid = Graph.save(params[:graph])
    json :uuid => uuid
  end

  post '/graphs/:uuid/snapshot' do
    url = Graph.snapshot(params[:uuid])
    json :url => url
  end

  put '/graphs/:uuid' do
    uuid = Graph.save(params[:uuid], params[:graph])
    json :uuid => uuid
  end

  post '/dashboards' do
    dashboard = Dashboard.save(params[:dashboard])
    json :dashboard => dashboard
  end

  post '/graphs/dashboards' do
    json Dashboard.add_graph(params[:dashboard], params[:uuid])
  end

  delete '/graphs/dashboards' do
    json Dashboard.remove_graph(params[:dashboard], params[:uuid])
  end

  delete '/graphs/:uuid' do
    Graph.destroy(params[:uuid])
  end

  delete '/dashboards/:slug' do
    Dashboard.destroy(params[:slug])
  end

  post '/snapshot' do
    filename = Graph.snapshot(params[:uuid], settings.snapshots['service'], File.join(settings.root, 'public'))
    json :filename => filename
  end

  # Routes that are entirely handled by Sammy/frontend
  # and just need to load the empty index
  %w{
    /graphs/workspace
    /graphs/new
    /graphs/:uuid
    /graphs/:uuid/snapshots
    /graphs
    /dashboards/:slug
    /dashboards
    /
  }.each do |path|
    get path do
      haml :index
    end
  end

  get '/stylesheets/:name.css' do
    content_type 'text/css'
    scss :"stylesheets/#{params[:name]}"
  end

  def default_graph
    {
      :options => settings.default_options,
      :targets => settings.default_metrics.collect {|m| m.is_a?(Array) ? m : [m, {}] }
    }
  end

end
