# Redirect the output to a file:
$stdout.reopen("bcf_log.txt", "w")
$stdout.sync = true
$stderr.reopen($stdout)

require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"

configure do
  enable :sessions
  set :session_secret, 'secret'
# set :erb, :escape_html => true
end

def runs_data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data/runs.yml", __FILE__)
  else
    File.expand_path("../data/runs.yml", __FILE__)
  end
end

def upload_run_data(run)
  runs_data = load_runs_data
  runs_data << run
  upload_runs_data(runs_data)
end

def upload_runs_data(runs_data)
  File.open(runs_data_path, 'w') do |file|
    file.write(YAML.dump(runs_data))
  end
  nil
end

def calc_duration(hrs, mins, secs)
  hrs * 60 * 60 + mins * 60 + secs
end

def next_run_id
  runs_data = load_runs_data
  last_id = runs_data.map { |run| run.id }.max || 0
  last_id + 1
end

helpers do
  # Helper functions (visible in templates).
end

class Run
  attr_reader :id, :date, :duration, :distance

  def initialize(date, hrs, mins, secs, distance)
    @date = date
    @duration = calc_duration(hrs, mins, secs)
    @distance = distance
    @id = next_run_id # can't use class var, since doesn't get stored in the yml
  end

  def date_pretty
    @date
  end

  def duration_pretty
    hrs, secs_rem = duration.divmod 3600
    mins, secs = secs_rem.divmod 60
    secs = secs.round(0)
    "#{hrs}:#{mins}:#{secs}"
  end

  def distance_pretty
    @distance.round(2)
  end
end

def load_runs_data
  runs_data = YAML.load_file(runs_data_path)
  runs_data ||= [] # in case runs_data is empty
end

before do
  # Run before each route is processed.
  #update_runs_data_from_yml
end

get '/' do
  redirect '/overview'
end

get '/overview' do
  erb :overview, layout: :layout
end

get '/by_run' do
  erb :by_run
end

# Menu button 'List':
get '/list' do
  redirect '/runs'
end

# List the runs:
get '/runs' do
  @runs_data = load_runs_data
  erb :runs
end

# Menu button 'Add run':
get '/add_run' do
  erb :add_run
end

# Add new run:
post '/runs/new' do
  date = params[:date]
  hrs = params[:hours].to_f
  mins = params[:minutes].to_f
  secs = params[:seconds].to_f
  distance = params[:distance].to_f
#
#  id = next_run_id
#  duration = calc_duration(hrs, mins, secs)
#  new_run = {
#    id: id,
#    date: date,
#    duration: duration,
#    distance: distance
#  }
  new_run = Run.new(date, hrs, mins, secs, distance)

  upload_run_data(new_run)
  session[:msg] = "New run added for #{date}"
  erb :add_run
end

# Delete a run:
get '/runs/delete/:run_id' do
  @runs_data = load_runs_data
  @run_id = params[:run_id]
  session[:msg] = "Are you sure you want to delete this run?"
  erb :delete_run
  #erb :layout, :layout => false do
  #  erb :runs do
  #    erb :delete_run
  #  end
  #end
  # erb :runs
end

post '/runs/delete/:run_id' do
  run_id = params[:run_id].to_i

  @runs_data = load_runs_data
  @runs_data.delete_if do |run|
    run.id == run_id
  end
  upload_runs_data(@runs_data)
  session[:msg] = "Okay, run deleted!"

  erb :runs
end


#not_found do
#  erb "Page not found!"
#end
