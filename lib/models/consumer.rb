class Consumer < ActiveRecord::Base
    has_many :consumer_beers, dependent: :destroy
    has_many :beers, through: :consumer_beers

    def self.handle_returning_consumer
        puts "Welcome back! What is your name?"
        name = gets.chomp.capitalize
        if !Consumer.find_by(name: name)
          TTY::Prompt.new.keypress("User not found. Please enter a valid name. Press any key to try again.")
          nil
        else
          Consumer.find_by(name: name)
        end
    end

    def self.handle_new_consumer
        name = TTY::Prompt.new.ask("Welcome to our program! What is your name?").capitalize
        age = TTY::Prompt.new.ask("What is your age?") { |q| q.in('21-130') }
        location = TTY::Prompt.new.ask("Where do you live?").capitalize
        gender = TTY::Prompt.new.select("What is your gender?", ["Male", "Female", "Other"])
        favorite_style = TTY::Prompt.new.select("What is your favorite style of beer?",
            Beer.beer_styles, per_page: 8)
        Consumer.create(name: name, age: age, location: location, gender: gender, favorite_style: favorite_style)
    end

    # Beer Profile

    def beer_profile
        TTY::Prompt.new.select("What do you want to see?") do |menu|
            menu.choice "My Fridge", -> {self.view_fridge}
            menu.choice "My Beer History", -> {self.beer_history_menu}
        end
    end

    def beer_history_menu
        # what stats do we want to include? Full history(list of beers consumed), stats(top 3 most drank beers, highest rated beers, breweries)
        # probably need several methods
        # this method will print out results of helper methods
        TTY::Prompt.new.select("What do you want to see?") do |menu|
            menu.choice "Quick Stats", -> {self.quick_stats}
            menu.choice "Full History", -> {self.full_beer_history}
        end
    end

    def fridge_contents
        beers_in_fridge = self.consumer_beers.select {|consumer_beer| consumer_beer.num_available > 0}
        beers_in_fridge.map { |consumer_beer| "#{consumer_beer.beer.name.pluralize}: #{consumer_beer.num_available}" }
    end

    def view_fridge
        puts "\n#{self.name}'s Fridge:"
        if fridge_contents == []
          puts "\n🍺 This fridge is empty! 🍺"
        else
          puts "\n#{fridge_contents.join("\n")}"
        end
    end

    def rated_beers
        self.consumer_beers.where.not(rating: nil)
    end

    def sort_beers(attribute) #helper
        rated_beers.sort_by { |beer| beer.send(attribute) }.reverse
    end

    def beer_consumption
        beer_consumed = sort_beers(:num_consumed)
        beer_consumed.map {|consumer_beer| "#{consumer_beer.beer.name} from #{consumer_beer.brewery.name}: #{consumer_beer.rating}/5;  #{consumer_beer.num_consumed} drank"}
    end

    def beer_ratings
        beer_rating = sort_beers(:rating)
        beer_rating.map {|consumer_beer| "#{consumer_beer.beer.name}: #{consumer_beer.rating}"}
    end

    #Tough Methods

    def brewery_consumed_count
        self.consumer_beers.map {|consumer_beer| {consumer_beer.brewery => consumer_beer.num_consumed}}
    end

    def brewery_frequency
        frequency_hash = Hash.new(0)
        brewery_consumed_count.each do |brew_hash|
            frequency_hash[brew_hash.keys.first] += brew_hash.values.first
        end
        frequency_hash.sort_by{ |brewery, count| count }.reverse
    end

    def print_brewery_frequency
        self.brewery_frequency.map {|brewery, count| "#{brewery.name}, beers consumed: #{count}"}
    end

    def quick_stats
        #top 3: most drank, highest rated, breweries
        puts "\nTop three most drank beers:\n#{beer_consumption[0..2].join("\n")}\n\nTop three highest rated beers:\n#{beer_ratings[0..2].join("\n")}\n\nTop three breweries:\n#{print_brewery_frequency[0..2].join("\n")}"
    end

    def full_beer_history
        puts "\n#{self.name}'s Beer History:"
        puts "\n#{beer_consumption.join("\n")}"
    end


    #Acquire Beer

    def rate_beer #helper
      TTY::Prompt.new.ask("Rate this beer from 0-5") { |q| q.in('0-5') }
    end

    def buy_drink_beer
        TTY::Prompt.new.select("Buy or drink beer?") do |menu|
            menu.choice "Buy beer", -> {self.choose_beer_to_buy}
            menu.choice "Drink beer", -> {self.drink_beer_menu}
        end
    end

    def choose_beer
        breweries_with_beers = Brewery.all.select {|brewery| brewery.beers != []}
        brewery_choice = TTY::Prompt.new.select("What brewery?", breweries_with_beers.pluck(:name))
        beer_choice = TTY::Prompt.new.select("What beer?", Brewery.find_by(name: brewery_choice).beers.pluck(:name))
        Beer.find_by(name: beer_choice)
    end

    def choose_beer_to_buy
        # add to num_available if ConsumerBeer instance exists or create new one
        chosen_beer = self.choose_beer
        quantity = TTY::Prompt.new.ask("How many?").to_i
        buy_beer(chosen_beer, quantity)
    end

    def buy_beer(chosen_beer, chosen_quantity)
        #binding.pry
        if !self.consumer_beers.find_by(beer_id: chosen_beer.id)
            ConsumerBeer.create(beer_id: chosen_beer.id, consumer_id: self.id, num_available: chosen_quantity)
        else
            new_num = self.consumer_beers.find_by(beer_id: chosen_beer.id).num_available + chosen_quantity
            self.consumer_beers.find_by(beer_id: chosen_beer.id).update(num_available: new_num)
        end
    end

    def drink_beer_menu
        TTY::Prompt.new.select("Would you like to drink from your fridge or go to the brewery?") do |menu|
            menu.choice "Drink from fridge", -> {self.choose_beer_from_fridge}
            menu.choice "Go to brewery", -> {self.choose_beer_from_brewery}
        end
    end

    def choose_beer_from_brewery
        chosen_beer = self.choose_beer
        drink_beer_from_brewery(chosen_beer)
    end

    def update_rating(beer)
        current_cbeer = self.consumer_beers.find_by(beer_id: beer.id)
        if !current_cbeer.rating
          self.rate_beer
        else
          update_rating = TTY::Prompt.new.select("Do you want to change your current rating of #{current_cbeer.rating}?", ["Yes", "No"])
          if update_rating == "Yes"
              self.rate_beer
          else
              current_cbeer.rating
          end
        end
    end

    def drink_beer_from_brewery(beer)
        # creates new ConsumerBeer instance with num_consumed = 1 and num_available = 0
        # or increases num_consumed by 1 for existing ConsumerBeer instance
        if !self.consumer_beers.find_by(beer_id: beer.id)
            rating = self.rate_beer
            ConsumerBeer.create(beer_id: beer.id, consumer_id: self.id, num_available: 0, num_consumed: 1, rating: rating)
        else
            rating = self.update_rating(beer)
            new_num = self.consumer_beers.find_by(beer_id: beer.id).num_consumed + 1
            self.consumer_beers.find_by(beer_id: beer.id).update(num_consumed: new_num, rating: rating)
        end
    end

    def choose_beer_from_fridge
        # provide list of beers in fridge
        if fridge_contents == []
            puts "\n🍺 This fridge is empty! Buy some beer! 🍺"
        else
            beer_choice = TTY::Prompt.new.select("What beer?", fridge_contents, per_page: 10)
            beer_name = beer_choice.split(": ")
            current_beer = Beer.find_by(name: beer_name[0].singularize)
            drink_beer_from_fridge(current_beer)
        end
    end

    def drink_beer_from_fridge(beer)
        # finds ConsumerBeer instance, increases num_consumed by 1, decreases num_available by 1
        rating = self.update_rating(beer)
        current_cbeer = self.consumer_beers.find_by(beer_id: beer.id)
        new_num_available = current_cbeer.num_available - 1
        new_num_consumed = current_cbeer.num_consumed + 1
        current_cbeer.update(num_available: new_num_available, num_consumed: new_num_consumed, rating: rating)
        puts "🍻 Cheers! You now have #{current_cbeer.num_available} #{beer.name}s left 🍻"
    end

    # see other users info

    def view_other_users
        other_user_name = TTY::Prompt.new.select("Which fellow drinker would you like to see more about?", Consumer.where.not(name: self.name).pluck(:name))
        other_user = Consumer.find_by(name: other_user_name)
        TTY::Prompt.new.select("What would you like to see about #{other_user_name}?") do |menu|
            menu.choice "View #{other_user_name}'s fridge", -> {other_user.view_fridge}
            menu.choice "View #{other_user_name}'s quick stats", -> {other_user.quick_stats}
        end
    end

    # view brewery info

    def view_breweries
        brewery_choice = TTY::Prompt.new.select("What brewery?", Brewery.pluck(:name))
        brewery = Brewery.find_by(name: brewery_choice)
        TTY::Prompt.new.select("What information would you like to see about #{brewery_choice}?") do |menu|
            menu.choice "View Menu", -> {self.view_brewery_menu(brewery)}
            menu.choice "View Stats", -> {self.view_brewery_stats(brewery)}
        end
    end

    def view_brewery_menu(brewery)
        puts "\n#{brewery.name}'s Beer Menu\n\n"
        if brewery.beers == []
          puts "#{brewery.name} has no beers"
        else
          brewery.display_beers
        end
    end

    def view_brewery_stats(brewery)
        # most popular beer
        # average rating
        # beers sold
        if brewery.consumer_beers == []
          puts "\n#{brewery.name} hasn't sold any beers yet"
        else
          self.print_brewery_rating(brewery)
          self.print_most_popular(brewery)
          self.print_beers_sold(brewery)
        end
    end

    def print_most_popular(brewery)
        puts "\nMost Popular Beer:"
        puts "#{brewery.most_popular[0].name}, #{brewery.most_popular[0].style}"
    end

    def print_brewery_rating(brewery)
        puts "\n#{brewery.name}'s Consumer Rating:"
        puts "#{brewery.brewery_rating}/5"
    end

    def print_beers_sold(brewery)
        puts "\nBeer Sales:"
        brewery.sold_beer_count.each do |beer, num_sold|
            puts "#{beer.name}: #{num_sold} sold"
        end
    end

    # delete account

    def delete_account
        confirm = TTY::Prompt.new.select("Are you sure you want to delete your account?", ["Yes", "No"])
        if confirm == "Yes"
            self.destroy
            puts "\nSorry to see you go!\n"
        end
        exit!
    end

end
