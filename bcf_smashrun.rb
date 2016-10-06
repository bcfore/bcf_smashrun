# frozen_string_literal: true

TO_REDIRECT_OUTPUT_TO_FILE = false
if TO_REDIRECT_OUTPUT_TO_FILE
  $stdout.reopen("log/bcf_log.txt", "w")
  $stdout.sync = true
  $stderr.reopen($stdout)
end

require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"
require "date"
require "yaml"

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def conditionally_create_path(data_path)
  unless File.exist? data_path
    File.open(data_path, 'w') {}
  end
end

def runs_data_path
  File.join(data_path, "runs.yml")
end

def prefs_data_path
  File.join(data_path, "prefs.yml")
end

def stats_data_path
  File.join(data_path, "stats.yml")
end

def load_runs_data
  conditionally_create_path(runs_data_path)
  runs_data = YAML.load_file(runs_data_path)
  runs_data || []
end

def load_prefs_data
  conditionally_create_path(prefs_data_path)
  prefs = YAML.load_file(prefs_data_path)
  prefs || default_prefs
end

def load_stats_data
  conditionally_create_path(stats_data_path)
  stats = YAML.load_file(stats_data_path)
  stats || calc_stats_hash(load_runs_data)
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

def update_stats(runs_data)
  stats = calc_stats_hash(runs_data)
  upload_data(stats, stats_data_path)
end

def calc_stats_hash(runs_data)
  net_duration = net_distance = max_distance = 0
  runs_data.each do |run|
    net_duration += run.duration
    net_distance += run.distance
    max_distance = run.distance if run.distance > max_distance
  end

  nb_runs = runs_data.size
  ave_pace = Run.calc_pace(net_duration, net_distance)
  ave_distance = (nb_runs > 0 ? net_distance / nb_runs : 0)
  ave_speed = Run.calc_speed(net_distance, net_duration)

  {
    nb_runs: nb_runs,
    ave_pace: Run.display_time(ave_pace),
    ave_distance: Run.display_float(ave_distance),
    ave_speed: Run.display_float(ave_speed),
    longest_run: Run.display_float(max_distance),
    total_distance: Run.display_float(net_distance)
  }
end

def next_run_id
  runs_data = load_runs_data
  last_id = runs_data.map(&:id).max || 0
  last_id + 1
end

helpers do
  # Helper functions (visible in templates).

  def h(param)
    Rack::Utils.escape_html(value)
  end

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

  def display_last_run_message
    runs_data = load_runs_data
    last_run = runs_data.max_by(&:date)
    return "No runs yet" if last_run.nil?

    last_run_date = Date.strptime(last_run.date, "%F")
    today = Date.today
    nb_days = (today - last_run_date).to_i

    if nb_days == 0
      "Today!"
    elsif nb_days == 1
      "Yesterday"
    elsif nb_days > 0
      "#{nb_days} days ago"
    else # should be excluded a priori
      "#{-1 * nb_days} days from now"
    end
  end
end

module Selectable
  def mark_as_selected
    @selected = true
  end

  def selected?
    @selected == true
  end
end

class Run
  include Selectable

  SORTABLE_METHODS_NAMES = %w(date duration distance speed pace).freeze

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
    Run.display_float(@distance)
  end

  def speed_pretty
    Run.display_float(@speed)
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

    [hrs, mins, secs.to_i]
  end

  def self.display_time(time)
    hrs, mins, secs = Run.time_in_hms(time)

    hrs_str = (hrs > 0 ? "#{hrs}:" : '')
    mins_str = (hrs > 0 ? format("%02.0f", mins) : mins.to_s) + ':'
    secs_str = format("%02.0f", secs)

    hrs_str + mins_str + secs_str
  end

  def self.display_float(n)
    format("%.2f", n)
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

module ErrorCheck
  def self.run_input(params)
    error_list = []
    error_list += ErrorCheck.date(params)
    error_list += ErrorCheck.duration(params)
    error_list + ErrorCheck.distance(params)
  end

  def self.date(params)
    date = params[:date]

    if date == ''
      ["The run date is missing"]
    elsif !(date =~ /\d{4}-\d{2}-\d{2}/)
      ["Invalid run date: " + date]
    elsif Date.strptime(date, "%F") > Date.today
      ["The run date cannot be in the future"]
    else
      []
    end
  end

  def self.duration(params)
    duration_errors = ErrorCheck.hrs_mins_secs(params)
    return duration_errors unless duration_errors.empty?

    hrs = params[:hours].to_i
    mins = params[:minutes].to_i
    secs = params[:seconds].to_i

    duration = Run.calc_duration(hrs, mins, secs)
    duration_errors +
      if duration == 0
        ["The total duration should be greater than 0"]
      elsif hrs > 0 && mins > 59
        # Allow either 0 hrs 90 minutes, or 1 hr 30 minutes,
        # but not 1 hr 90 minutes.
        ["'mins' should be between 0 and 59"]
      else
        []
      end
  end

  def self.distance(params)
    dist = params[:distance]

    if !valid_nonneg_float?(dist)
      ["The distance should be a number greater than 0"]
    elsif dist.to_f == 0
      ["The distance should be greater than 0"]
    else
      []
    end
  end

  def self.hrs_mins_secs(params)
    errors = []

    errors += ErrorCheck.hrs(params)
    errors += ErrorCheck.mins(params)
    errors += ErrorCheck.secs(params)
    errors.delete_if(&:nil?)
  end

  def self.hrs(params)
    hrs = params[:hours]
    if !valid_nonneg_integer?(hrs)
      ["'hrs' should be an integer greater than or equal to 0"]
    else
      []
    end
  end

  def self.mins(params)
    mins = params[:minutes]
    if !valid_nonneg_integer?(mins)
      ["'mins' should be an integer greater than or equal to 0"]
    else
      []
    end
  end

  def self.secs(params)
    secs = params[:seconds]
    if !valid_nonneg_integer?(secs) || secs.to_i > 59
      ["'secs' should be an integer between 0 and 59"]
    else
      []
    end
  end

  def self.valid_nonneg_integer?(nb_string)
    nb = nb_string.strip
    # nb.gsub!(/^0*/, '')
    nb.gsub!(/\.*$/, '')

    # nb.to_i.to_s == nb_string
    !(nb =~ /\D/)
  end

  def self.valid_nonneg_float?(nb_string)
    nb = nb_string.strip
    nb.sub!(/\./, '')

    !(nb =~ /\D/)
  end
end

def session_msg_for_errors(error_list)
  return if error_list.empty?

  if error_list.size == 1
    # "Error: "
    "There's an error in your input:"
  else
    "There are some errors in your input:"
  end
end

get '/' do
  session[:selected_menu_item] = :welcome
  session[:sub_heading] = "Welcome!"
  erb :welcome
end

get '/overview' do
  session[:selected_menu_item] = :overview
  session[:sub_heading] = "Overall running report"

  @stats = load_stats_data
  erb :overview
end

# Menu button 'List' (the runs):
get '/runs' do
  session[:selected_menu_item] = :runs
  session[:sub_heading] = "List of all runs"

  # clear_runs_data
  @runs_data = load_sorted_runs_data

  erb :runs
end

# Sort the runs (by clicking on column headers):
get '/runs/sort' do
  if params[:by] && !Run::SORTABLE_METHODS_NAMES.include?(params[:by])
    session[:msg] = "Error: Invalid sort criterion."
    params.delete(:by)
    redirect '/runs'
  end

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

  @run_id = params[:run_id].to_i
  selected_runs = @runs_data.select { |run| run.id == @run_id }
  run = selected_runs.first

  if run
    # To turn on the css class "selected":
    run.mark_as_selected

    # The delete_run.erb includes the form buttons.
    @is_deletion_mode = true
    session[:msg] = "Are you sure you want to delete this run?"
    session[:delete_id] = @run_id

    erb :runs do
      erb :delete_run
    end
  else
    session[:msg] = "Page not found!"
    redirect '/runs'
  end
end

post '/runs/delete' do
  run_id = session.delete(:delete_id)

  @runs_data = load_sorted_runs_data
  @runs_data.delete_if do |run|
    run.id == run_id
  end
  upload_data(@runs_data, runs_data_path)
  session[:msg] = "Okay, run deleted!"

  redirect '/runs'
end

# Edit a run:
get '/runs/edit/:run_id' do
  runs_data = load_sorted_runs_data

  run_id = params[:run_id].to_i
  selected_runs = runs_data.select { |run| run.id == run_id }
  run = selected_runs.first

  if run
    @date = run.date
    @hrs, @mins, @secs = Run.time_in_hms(run.duration)
    @distance = run.distance
    @is_edit = true

    session[:edit_id] = run_id
    session[:msg] = "Edit your run info"
    erb :run_info
  else
    session[:msg] = "Page not found!"
    redirect '/runs'
  end
end

post '/runs/edit' do
  @error_list = ErrorCheck.run_input(params)
  run_id = session[:edit_id]

  if @error_list.empty?
    date = params[:date]
    hrs = params[:hours].to_i
    mins = params[:minutes].to_i
    secs = params[:seconds].to_i
    distance = params[:distance].to_f

    modified_run = Run.new(date, hrs, mins, secs, distance)
    modify_run(run_id, modified_run)

    key = "run_id_#{run_id}".to_sym
    session[key] = "Updated!"
    session.delete(:edit_id)

    redirect '/runs'
  else
    status 422
    @is_edit = true
    session[:msg] = session_msg_for_errors(@error_list)

    erb :run_info do
      erb :error_list
    end
  end
end

# Menu button 'Add run':
get '/add_run' do
  session[:selected_menu_item] = :add_run

  @date = Date.today.strftime("%F")
  @hrs = @mins = @secs = 0
  @distance = 0

  session[:sub_heading] = "Input your run info"
  erb :run_info
end

# Add new run:
post '/runs/new' do
  @error_list = ErrorCheck.run_input(params)

  if @error_list.empty?
    date = params[:date]
    hrs = params[:hours].to_i
    mins = params[:minutes].to_i
    secs = params[:seconds].to_i
    distance = params[:distance].to_f

    new_run = Run.new(date, hrs, mins, secs, distance)
    upload_run(new_run)

    key = "run_id_#{new_run.id}".to_sym
    session[key] = "New!"
    redirect '/runs'
  else
    status 422
    session[:msg] = session_msg_for_errors(@error_list)

    erb :run_info do
      erb :error_list
    end
  end
end

not_found do
  session[:msg] = "Page not found!"
  redirect '/runs'
end
