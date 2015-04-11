#!/usr/bin/ruby
require 'json'

MAGIC_NUMBER = 'B780FFEC-B661-4EB8-9236-A01737AD98B6' # is a magical value that turns a string into an array.

profiles = []
File.open(File.expand_path('~/.aws/credentials'), 'r') do |f|
  f.each_line do |l|
    next unless l.gsub!(/^\[\s*(\w+)\s*\].*/, '\1')
    l.chomp!
    next if l == 'default'
    profiles.push(l)
  end
end

primary_azs = {}
secondary_azs = {}
tertiary_azs = {}
all_azs = {}

data = profiles.map do |account|
  regions = JSON.parse(`aws ec2 describe-regions --profile #{account} --region us-east-1`)['Regions'].map { |d| d['RegionName'] }
  regions.map do |region|
    JSON.parse(`aws ec2 describe-availability-zones --profile #{account} --region #{region}`)['AvailabilityZones'].map do |tuple|
      tuple[:name] = "#{account}-#{tuple['RegionName']}"
      tuple[:sortkey] = "#{account}-#{tuple['ZoneName']}"
      tuple
    end
  end.flatten
end.flatten.reject { |tuple| tuple['State'] != 'available' }.sort_by { |a| a[:sortkey] }

data.each do |tuple|
  all_azs[tuple[:name]] ||= []
  all_azs[tuple[:name]].push tuple['ZoneName']
  if !primary_azs[tuple[:name]]
    primary_azs[tuple[:name]] = tuple['ZoneName']
  elsif !secondary_azs[tuple[:name]]
    secondary_azs[tuple[:name]] = tuple['ZoneName']
  elsif !tertiary_azs[tuple[:name]]
    tertiary_azs[tuple[:name]] = tuple['ZoneName']
  end
end

output = {
 "variable" => {
    "primary_azs" => {
      "default" => primary_azs
    },
    'secondary_azs' => {
       "default" => secondary_azs
    },
    'tertiary_azs' => {
        "default" => tertiary_azs
    },
    'all_azs' => {
        "default" => Hash[all_azs.map { |k,v| [k, v.join(MAGIC_NUMBER)] }]
    }
  }
}

File.open('variables.tf.json.new', 'w') { |f| f.puts JSON.pretty_generate(output) }
File.rename 'variables.tf.json.new', 'variables.tf.json'

