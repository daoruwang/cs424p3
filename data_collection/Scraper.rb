#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'uri'
require 'net/http'
require 'chronic'
require "sqlite3"
require 'progressbar'


#TODO add method that will write the data into flat file OR database
module Scraper
  #Downloads data and parses it into three buckets seasons, episodes, and phrases
  DUMP_FILE_NAME = "scraped_rb_dump.bin".freeze
  SITE_DIRECTORY = "/webreports".freeze
  BANNED_LOCATIONS = %w(UNSPECIFIED/INTERNATIONAL ALBERTA,CANADA).freeze


  def self.open(url_string)
    url = URI.parse(url_string)
    host_rel_path = "#{url.scheme}://#{url.host + SITE_DIRECTORY}"
    request = Net::HTTP.new(url.host, url.port)
    request.read_timeout = 60
    try = 0
    response = nil
    begin
      response = request.get(url.request_uri).body
    rescue Exception => e
      try+=1
      if try < 10
        retry
      end
      puts "FAILED TO OPEN: " + url_string.to_s
      puts e
    end
    response
  end

  def self.dump_file_path
    File.join File.expand_path(File.dirname(__FILE__)), DUMP_FILE_NAME
  end

  def self.scrape
    host_rel_path = "http://www.nuforc.org#{SITE_DIRECTORY}"

    #Represent tables
    states = []
    sightings = []
    rows = Nokogiri::HTML(open(host_rel_path + "/ndxloc.html")).xpath("//table/tbody/tr/td[1]//a")
    pbar = ProgressBar.new("Loading...", rows.length - BANNED_LOCATIONS.length)
    rows.each_with_index do |sighting_link_html, i|
      state = {}
      state[:sightings_url] = "#{host_rel_path}/#{sighting_link_html["href"]}"
      state[:name] = sighting_link_html.content
      next if BANNED_LOCATIONS.include? state[:name]
      pbar.inc
      states << state 
      html = open(state[:sightings_url])
      next unless html
      Nokogiri::HTML(html).xpath("//table/tbody/tr").each do |sighting_html|
        sighting = {}
        columns = sighting_html.xpath "td"
        #ONLY 2 rows out of the whole set have these problems, really broken HTML in summary, lets ignore these records
        if columns.length == 7 
          sighting[:occurred_at] = columns[0].content.strip_html.strip
          sighting[:city] = columns[1].content.strip_html.strip
          sighting[:state] = columns[2].content.strip_html.strip
          state[:name_abbreviation] ||= sighting[:state].strip
          sighting[:shape] = columns[3].content.strip_html.strip
          sighting[:duration] = columns[4].content.strip_html.strip
          sighting[:summary_description] = columns[5].content.strip_html.strip
          sighting[:posted_at] = columns[6].content.strip_html.strip
          sighting[:sighting_detail_url] = "#{host_rel_path}/#{columns.first.xpath(".//a").first["href"]}"
        else
          sighting[:broken] = sighting_html.content.strip
        end
        sightings << sighting
        if sighting[:sighting_detail_url]
          html = open(sighting[:sighting_detail_url])
          next unless html
          details_html = Nokogiri::HTML(html).xpath "//table/tbody/tr/td"
          if details_html.length < 2
            reported_at = details_html[0].content.to_s.strip_html.scan /Reported:\s(.*?)\s.*[PAM]{2}\s(\d{1,2}:\d{1,2})/
            if reported_at.one?
              sighting[:reported_at] = reported_at.first.map(&:strip).join(" ").strip
            end
            full_description = details_html[1].content.strip_html.strip
            unless full_description.empty?
              sighting[:full_description] = full_description.strip
            end
          end
        end
      end
    end
    pbar.finish
    result = {:states => states, :sightings => sightings}
    cached_result = Marshal.dump result
    file_path = self.dump_file_path
    f = File.new file_path, "w" 
    f.write cached_result
    f.close
    result
  end

  def self.createdb
    raise "#{DUMP_FILE_NAME} not found" unless File.exists? self.dump_file_path
    result = Marshal.load IO.read(self.dump_file_path)

    result[:sightings].delete_if{|sighting| !sighting[:broken].nil? }

    db = SQLite3::Database.new('ufo.db')
    db.transaction do
      create_query  = %{

        DROP TABLE IF EXISTS states;
        CREATE TABLE states (
          id INTEGER PRIMARY KEY, 
          name_abbreviation STRING, 
          name STRING);

        DROP TABLE IF EXISTS counties;
        CREATE TABLE counties (
          id INTEGER PRIMARY KEY,
          state_id INTEGER,
          name STRING
        );

        DROP TABLE IF EXISTS cities;
        CREATE TABLE cities (
          id INTEGER PRIMARY KEY,
          county_id integer,
          state_id integer,
          name STRING,
          lat INTEGER,
          lon INTEGER
        );

        DROP TABLE IF EXISTS shapes;
        CREATE TABLE shapes (
          id INTEGER PRIMARY KEY,
          name STRING
        );
        
        DROP TABLE IF EXISTS sightings;
        CREATE TABLE sightings (
          id INTEGER PRIMARY KEY,
          city_id INTEGER,
          shape_id INTEGER,
          summary_description STRING,
          full_description STRING, 
          occurred_at TIMESTAMP,
          reported_at TIMESTAMP,
          posted_at TIMESTAMP
        );
      }

      db.execute_batch create_query

      # feeding data to database   
      puts "Inserting states"
      result[:states].each do |state|
        db.execute "INSERT INTO states (name, name_abbreviation) VALUES (?,?)", state[:name], state[:name_abbreviation]
      end
      #TODO find county for each city, insert conties into table, and map cities to counties
      puts "Inserting cities"
      result[:sightings].map{|sighting| [sighting[:city], sighting[:state] ] }.uniq.each do |city_state|
        db.execute "INSERT INTO cities (name, state_id) VALUES (?, (SELECT id FROM states WHERE name_abbreviation LIKE ?))", city_state.first, city_state.last
      end

      puts "Inserting shapes"
      result[:sightings].map{|sighting| sighting[:shape].strip }.uniq.each do |shape|
        db.execute "INSERT INTO shapes (name) VALUES (?)", shape
      end

      puts "Inserting sightings"
      result[:sightings].each do |sighting|
        db.execute "INSERT INTO sightings (city_id, shape_id, summary_description, full_description, occurred_at, reported_at, posted_at)
                                  VALUES((SELECT id FROM cities WHERE name LIKE ?), (SELECT id FROM shapes WHERE name LIKE ?), ?, ?, ?, ?, ?)",
                                  sighting[:city], sighting[:shape], sighting[:summary_description], sighting[:full_description], 
                                  sighting[:occurred_at].to_date(:db),
                                  sighting[:reported_at] ? sighting[:reported_at].to_date(:db) : nil, 
                                  sighting[:posted_at].to_date(:db)
      end
    end
  end
end

#Extens string class to be able to get rid of any text that is within HTML elements
class String
  def strip_html
      self.gsub(/<script[^>]*>(.|\s)*?<\/script>/i, "").
           gsub(/<style[^>]*>(.|\s)*?<\/style>/i, "").
           gsub(/<!--(.|\s)*?-->/, "").
           gsub(/(&nbsp;)+|\s+/," ").
           gsub(/<\/?[^>]*>/, "").
           squeeze(" ")
  end 

  def to_date(type = nil)
    return nil if self.empty?
    result = self.split("/")
    least_significant_year = result.last
    if "20#{least_significant_year}".to_i > Time.now.year
      year = "19"
    else
      year = "20"
    end
    result = Chronic.parse [result[0], result[1], year + least_significant_year].join("/")
    if type and type == :db and result
      result = result.strftime "%Y.%m.%d %H:%M:%S"
    end
    result
  end
end

if ARGV[0] == "scrape"
  Scraper.scrape
end
