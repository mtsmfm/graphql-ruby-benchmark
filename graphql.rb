require 'bundler/inline'

GRAPHQL_VERSION = ENV.fetch('GRAPHQL_VERSION')
USE_GITHUB = ENV.fetch('USE_GITHUB')

gemfile do
  source 'https://rubygems.org'

  gem 'pry-byebug'
  if USE_GITHUB == '1'
    gem 'graphql', github: 'rmosolgo/graphql-ruby', ref: GRAPHQL_VERSION
  else
    gem 'graphql', GRAPHQL_VERSION

    if Gem::Version.new("0.8.0") <= Gem::Version.new(GRAPHQL_VERSION) && Gem::Version.new(GRAPHQL_VERSION) < Gem::Version.new("0.9.0")
      gem 'celluloid', '0.17.4'
    end
  end
end

require "json"

FIELD_COUNT = ENV.fetch("FIELD_COUNT").to_i
ARTICLES_COUNT = ENV.fetch("OBJECT_COUNT").to_i

ALL_ARTICLES = ARTICLES_COUNT.times.map do |i|
  {title: "title#{i}"}
end

if Gem::Version.new(GraphQL::VERSION) <= Gem::Version.new("0.1.0")
  ArticleType = GraphQL::ObjectType.new do
    name 'Article'
    self.fields = FIELD_COUNT.times.to_h do |i|
      [
        :"title#{i}",
        GraphQL::Field.new {|f|
          f.type !type.String
          f.resolve -> (object, *) { object[:title] }
        }
      ]
    end
  end

  QueryType = GraphQL::ObjectType.new do
    name 'Query'
    self.fields = {
      articles: GraphQL::Field.new {|f|
        f.type GraphQL::ListType.new(of_type: ArticleType)
        f.resolve -> (object, *) { ALL_ARTICLES }
      }
    }
  end
elsif Gem::Version.new(GraphQL::VERSION) < Gem::Version.new("0.5.0")
  ArticleType = GraphQL::ObjectType.new do |t, type, field|
    t.name 'Article'
    t.fields(FIELD_COUNT.times.to_h do |i|
      [
        :"title#{i}",
        GraphQL::Field.new {|f|
          f.type !type.String
          f.resolve -> (object, *) { object[:title] }
        }
      ]
    end)
  end

  QueryType = GraphQL::ObjectType.new do |t, types, field|
    t.name 'Query'
    t.fields({
      articles: GraphQL::Field.new {|f|
        f.type GraphQL::ListType.new(of_type: ArticleType)
        f.resolve -> (object, *) { ALL_ARTICLES }
      },
    })
  end
elsif Gem::Version.new(GraphQL::VERSION) < Gem::Version.new("1.8.0")
  ArticleType = GraphQL::ObjectType.define do
    name 'Article'
    FIELD_COUNT.times do |i|
      field :"title#{i}", !types.String do
        resolve -> (object, *) { object[:title] }
      end
    end
  end

  QueryType = GraphQL::ObjectType.define do
    name 'Query'
    field :articles, types[!ArticleType] do
      resolve -> (*) { ALL_ARTICLES }
    end
  end
else
  class ArticleType < GraphQL::Schema::Object
    FIELD_COUNT.times do |i|
      field "title#{i}", String, null: false

      define_method "title#{i}" do
        object[:title]
      end
    end
  end

  class QueryType < GraphQL::Schema::Object
    field :articles, [ArticleType], null: true

    def articles
      ALL_ARTICLES
    end
  end
end

if Gem::Version.new(GraphQL::VERSION) <= Gem::Version.new("0.18.0")
  TestSchema = GraphQL::Schema.new(
    query: QueryType,
    mutation: nil
  )
elsif Gem::Version.new(GraphQL::VERSION) < Gem::Version.new("1.8.0")
  TestSchema = GraphQL::Schema.define do
    query QueryType
  end
else
  class TestSchema < GraphQL::Schema
    query QueryType
  end
end

QUERY = <<GQL
  {
    articles { #{FIELD_COUNT.times.map {|i| "title#{i}" }.join(",")} }
  }
GQL

EXPECTATION = {
  "data" => {
    "articles" => ARTICLES_COUNT.times.map do |i|
      FIELD_COUNT.times.to_h do |j|
        ["title#{j}", "title#{i}"]
      end
    end
  }
}

def execute
  if Gem::Version.new(GraphQL::VERSION) < Gem::Version.new("0.3.0")
    {
      "data" => GraphQL::Query.new(TestSchema, QUERY).result['data'][nil]
    }
  elsif Gem::Version.new(GraphQL::VERSION) < Gem::Version.new("0.10.0")
    GraphQL::Query.new(TestSchema, QUERY).result
  else
    TestSchema.execute(QUERY).to_h
  end
end

unless execute == EXPECTATION
  raise "something wrong"
end
