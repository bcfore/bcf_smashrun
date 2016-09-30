# Redirect the output to a file:
$stdout.reopen("bcf_log.txt", "w")
$stdout.sync = true
$stderr.reopen($stdout)

require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"
require "date"

configure do
  enable :sessions
  set :session_secret, 'secret'
# set :erb, :escape_html => true
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def runs_data_path
  File.join(data_path, "runs.yml")
end

def prefs_data_path
  File.join(data_path, "prefs.yml")
end

def load_runs_data
  runs_data = YAML.load_file(runs_data_path)
  runs_data ||= [] # in case runs_data is empty
end

def load_prefs_data
  prefs = YAML.load_file(prefs_data_path)
  prefs ||= default_prefs
end

def load_sorted_runs_data
  runs_data = load_runs_data
  prefs = load_prefs_data

  runs_data.sort_by!(&prefs[:sort_by])
  runs_data.reverse! if prefs[:sort] == 'desc'

  runs_data
end

def default_prefs
  {
    sort_by: :date,
    sort: 'asc'
  }
end

def modify_run(run_id, new_run_info)
  runs_data = load_runs_data
  orig_run = runs_data.select { |run| run.id == run_id }.first
  orig_run.modify(new_run_info)
  upload_data(runs_data, runs_data_path)
end

def upload_run(run)
  runs_data = load_runs_data
  runs_data << run
  upload_data(runs_data, runs_data_path)
end

def upload_data(data, data_path)
  File.open(data_path, 'w') do |file|
    file.write(YAML.dump(data))
  end
  nil
end

def clear_runs_data
  runs_data = []
  upload_data(runs_data, runs_data_path)
end

def next_run_id
  runs_data = load_runs_data
  last_id = runs_data.map { |run| run.id }.max || 0
  last_id + 1
end

helpers do
  # Helper functions (visible in templates).

  def display_sort_symbol(col_name)
    prefs = load_prefs_data

    if prefs[:sort_by].to_s == col_name
      if load_prefs_data[:sort] == 'asc'
        '&#9650;'
      else
        '&#9660;'
      end
    else
      '&#160;&#160;'
    end
  end

  def display_notification(run)
    key = "run_id_#{run.id}".to_sym
    if session[key]
      session.delete(key)
    end
  end
end

module Selectable
  def mark_as_selected
    @selected = true
  end

  def is_selected?
    @selected == true
  end
end

class Run
  include Selectable

  attr_reader :id, :date, :duration, :distance, :speed, :pace

  def initialize(date, hrs, mins, secs, distance)
    @date = date
    @duration = Run.calc_duration(hrs, mins, secs)
    @distance = distance

    update_calculated_quantities!

    @id = next_run_id # can't use class var, since doesn't get stored in the yml
  end

  def date_pretty
    @date
  end

  def duration_pretty
    Run.display_time(@duration)
  end

  def distance_pretty
    format("%.2f", @distance)
  end

  def speed_pretty
    format("%.2f", speed)
  end

  def pace_pretty
    Run.display_time(@pace)
  end

  def self.calc_duration(hrs, mins, secs)
    hrs * 60 * 60 + mins * 60 + secs
  end

  def self.calc_speed(distance, duration)
    # In kph
    return 0 if duration == 0
    distance * 3600 / duration
  end

  def self.calc_pace(duration, distance)
    # In 'time per km'
    return 0 if distance == 0
    duration / distance
  end

  def self.time_in_hms(time)
    hrs, secs_rem = time.divmod 3600
    mins, secs = secs_rem.divmod 60

    [hrs, mins, secs]
  end

  def self.display_time(time)
    hrs, mins, secs = Run.time_in_hms(time)

    hrs_str = ( hrs > 0 ? "#{hrs}:" : '' )
    mins_str = ( hrs > 0 ? format("%02.0f", mins) : mins.to_s ) + ':'
    secs_str = format("%02.0f", secs)

    hrs_str + mins_str + secs_str
  end

  def modify(new_run_info)
    @date = new_run_info.date
    @duration = new_run_info.duration
    @distance = new_run_info.distance

    update_calculated_quantities!
  end

  def update_calculated_quantities!
    @speed = Run.calc_speed(@distance, @duration)
    @pace = Run.calc_pace(@duration, @distance)
  end
end

before do
  # Run before each route is processed.
  #update_runs_data_from_yml
end

get '/' do
  redirect '/overview'
end

get '/overview' do
  session[:selected_menu_item] = 1
  erb :overview
end

get '/by_run' do
  session[:selected_menu_item] = 2
  erb :by_run
end

# Menu button 'List' (the runs):
get '/runs' do
  session[:selected_menu_item] = 3

  # clear_runs_data
  @runs_data = load_sorted_runs_data

  erb :runs
end

# Sort the runs (by clicking on column headers):
get '/runs/sort' do
  # Initially I didn't have this as a separate route, so
  # no need to upload (then immediately download) the runs data.
  # But then it switches asc/desc with every page refresh.

  prefs = load_prefs_data
  prefs[:sort_by] = params[:by].to_sym unless params[:by].nil?

  prefs[:sort] =
    if prefs[:sort] == 'asc'
      'desc'
    else
      'asc'
    end

  upload_data(prefs, prefs_data_path)

  redirect '/runs'
end

# Delete a run:
get '/runs/delete/:run_id' do
  @runs_data = load_sorted_runs_data

  # To turn on the css class "selected":
  @run_id = params[:run_id].to_i
  selected_runs = @runs_data.select { |run| run.id == @run_id }
  selected_runs.each(&:mark_as_selected)

  # The delete_run.erb includes the 'Are you sure?' warning.
  @is_deletion_mode = true
  erb :runs do
    erb :delete_run
  end
end

post '/runs/delete/:run_id' do
  run_id = params[:run_id].to_i

  @runs_data = load_sorted_runs_data
  @runs_data.delete_if do |run|
    run.id == run_id
  end
  upload_data(@runs_data, runs_data_path)
  session[:msg] = "Okay, run deleted!"

  erb :runs
end

# Edit a run:
get '/runs/edit/:run_id' do
  runs_data = load_sorted_runs_data

  run_id = params[:run_id].to_i
  selected_runs = runs_data.select { |run| run.id == run_id }
  run = selected_runs.first

  @action = "edit/#{run_id}"
  @date = run.date
  @hrs, @mins, @secs = Run.time_in_hms(run.duration)
  @distance = run.distance
  @button_label = 'Edit run'

  session[:msg] = "Edit your run info"
  erb :run_info
end

post '/runs/edit/:run_id' do
  run_id = params[:run_id].to_i

  date = params[:date]
  hrs = params[:hours].to_f
  mins = params[:minutes].to_f
  secs = params[:seconds].to_f
  distance = params[:distance].to_f

  modified_run = Run.new(date, hrs, mins, secs, distance)
  modify_run(run_id, modified_run)

  key = "run_id_#{run_id}".to_sym
  session[key] = "Updated!"
  session[:msg] = "Run info modified for #{date}"

  redirect '/runs'
end

# Menu button 'Add run':
get '/add_run' do
  session[:selected_menu_item] = 4

  @action = 'new'
  @date = Date.today.strftime("%F")
  @hrs, @mins, @secs = [0, 0, 0]
  @distance = nil
  @button_label = 'Add run'

  session[:msg] = "Input your run info"
  erb :run_info
end

# Add new run:
post '/runs/new' do
  date = params[:date]
  hrs = params[:hours].to_f
  mins = params[:minutes].to_f
  secs = params[:seconds].to_f
  distance = params[:distance].to_f

  new_run = Run.new(date, hrs, mins, secs, distance)
  upload_run(new_run)

  key = "run_id_#{new_run.id}".to_sym
  session[key] = "New!"
  session[:msg] = "New run added for #{date}"

  redirect '/runs'
end

#not_found do
#  erb "Page not found!"
#end
