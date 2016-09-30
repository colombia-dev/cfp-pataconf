# This script gets all the open PR for `colombia-dev/cfp-pataconf` and for each
# one get the +1 reactions (and who added that reaction).

require 'pp'
require 'bundler'

Bundler.require(:default)

# Some basic classes, because objects are good and hashes are bad
class PullRequest
  def initialize(raw)
    @raw = raw
  end

  def id
    @raw[:number]
  end

  def user_id
    @raw[:user][:id]
  end

  def title
    @raw[:title]
  end
end

class Reaction
  attr_accessor :pull_request

  def initialize(raw, pull_request: nil)
    @raw = raw
    @pull_request = pull_request
  end

  def user
    @user ||= User.new(@raw[:user])
  end

  def pull_request_id
    pull_request.id
  end

  def user_id
    user.id
  end

  def content
    @raw[:content]
  end

  # We'll only accept +1 reactions and you cannot vote for yourself.
  def valid?
    content == '+1' && user_id != pull_request.user_id
  end

  def created_at
    @raw[:created_at]
  end
end

class User
  def initialize(raw)
    @raw = raw
    @reactions = Array.new
  end

  def id
    @raw[:id]
  end

  def login
    @raw[:login]
  end

  def add_reaction(reaction)
    @reactions << reaction
  end

  # Reactions are sorted by newest first
  def reactions
    @reactions.sort_by(&:created_at).reverse
  end
end


repo = 'colombia-dev/cfp-pataconf'
login = ENV['GH_LOGIN'] || 'nhocki'
client = Octokit::Client.new(login: login, password: ENV['GH_TOKEN'], auto_paginate: true)

raw_pulls = client.pull_requests(repo, state: 'open').map do |raw|
  PullRequest.new(raw)
end

reactions = raw_pulls.flat_map do |pull|
  puts "Getting reactions for PR ##{pull.id}"

  # This is ugly as fuck, but the reactions API is in beta state so you gotta accept squirrel-girl-preview
  client.issue_reactions(repo, pull.id, accept: 'application/vnd.github.squirrel-girl-preview').map do |raw|
    Reaction.new(raw, pull_request: pull)
  end
end.delete_if { |reaction| !reaction.valid? }

puts "\n\n"

# Create a hash of `user_id => user_object` so lookup is really easy
users = reactions.map(&:user).map { |user| [user.id, user] }.to_h

# Create a hash of `pull_request_number => pull_request` so lookup is really easy
pulls = raw_pulls.map { |pull| [pull.id, pull] }.to_h

reactions.each do |reaction|
  users[reaction.user_id].add_reaction(reaction)
end

# Votes is a hash from `pull_request_number => [user_that_voted, user_that_voted]`
votes = Hash.new { |hash, key| hash[key] = Array.new }

users.each do |_id, user|
  # Only count the last 5 reactions for each user.
  user.reactions.take(5).each do |reaction|
    votes[reaction.pull_request_id] << user.login
  end
end

# Since hashes are not sorted, get an array of PR numbers that is sorted by the
# number of votes that a talk got.
results = raw_pulls.map(&:id).sort_by! do |talk_id|
  -votes[talk_id].count
end

puts results.map { |talk| pulls[talk].title }

# Helper function to know who voted for what
def reactions_by_user(login, users)
  u = users.values.find { |u| u.login == login }
  u.reactions.map { |x| x.pull_request.title }
end

binding.pry
