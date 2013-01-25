require 'spec_helper'

if defined? ActiveRecord
  describe MoneyRails::ActiveRecord::Monetizable do
    # Class definition setup
    ####
    let(:model_class) do
      Class.new do
        include ActiveModel::Validations
        include ActiveModel::Validations::Callbacks
        include ActiveModel::Dirty

        include MoneyRails::ActiveRecord::Monetizable

        ## ActiveModel::Dirty stuff
        define_attribute_methods [:price_cents]

        attr_accessor :price_cents, :price_currency
      end
    end

    subject(:model) { validation_class.new }

    before(:each) do
      stub_const('BaseModel', model_class)
      stub_const('ExampleModel', validation_class)
    end

    # Specs
    ####

    describe "monetize" do
      let(:validation_class) do
        Class.new(model_class) do
          monetize :price_cents
        end
      end

      it "inherits monetized_attributes from parent classes" do
        Class.new(validation_class).monetized_attributes.should == validation_class.monetized_attributes
      end

      context "when the attribute is assigned a valid string" do
        before(:each) { model.price = "42" }

        it "attaches a Money object to model field" do
          model.price.should be_a(Money)
        end

        it "returns the expected money amount as a Money object" do
          model.price.should == Money.new(4200, "EUR")
        end
      end

      context "when the attribute is assigned a Money object" do
        before(:each) { model.price = Money.new(3210, "USD") }

        it { should be_valid }
        specify { model.price_cents.should == 3210 }
      end

      context "with an :as argument" do
        let(:validation_class) do
          Class.new(model_class) do
            monetize :price_cents, :as => :cost
          end
        end

        it "generates a money field with the specified name" do
          model.cost = 42
          model.cost.should == Money.new(4200, "EUR")
        end
      end

      it "validates numericality of the monetized attribute" do
        model.price_cents = "foo"
        model.should_not be_valid

        model.price_cents = 2000
        model.should be_valid
      end

      it "validates numericality on the generated money attribute" do
        model.price = "some text"
        model.should_not be_valid

        model.price = Money.new(320, "USD")
        model.should be_valid
      end

      it "fails validation with the proper error message if money value is invalid decimal" do
        model.price = "12.23.24"
        model.should_not be_valid
        model.errors[:price].first.should match(/Must be a valid/)
      end

      it "fails validation with the proper error message if money value is nothing but periods" do
        model.price = "..."
        model.should_not be_valid
        model.errors[:price].first.should match(/Must be a valid/)
      end

      it "fails validation with the proper error message if money value has invalid thousands part" do
        model.price = "12,23.24"
        model.should_not be_valid
        model.errors[:price].first.should match(/Must be a valid/)
      end

      context "with numericality validations" do
        let(:validation_class) do
          Class.new(model_class) do
            monetize :price_cents, :allow_nil => true,
              :numericality => {
               :greater_than_or_equal_to => 0,
               :less_than_or_equal_to => 10000,
               :message => "Must be greater than zero and less than $10k"
              }
          end
        end

        it "fails validation with the proper error message using numericality validations" do
          model.price = "-123"
          model.valid?.should be_false
          model.errors[:price].first.should match(/Must be greater than zero and less than \$10k/)

          model.price = "123"

          model.valid?.should be_true

          model.price = "10001"
          model.valid?.should be_false
          model.errors[:price].first.should match(/Must be greater than zero and less than \$10k/)
        end
      end

      it "passes validation if money value has correct format" do
        model.price = "12,230.24"
        model.should be_valid
      end

      it "uses i18n currency format when validating" do
        I18n.locale = "en-GB"
        Money.default_currency = Money::Currency.find('EUR')
        "12.00".to_money.should == Money.new(1200, :eur)
        transaction = Transaction.new(amount: "12.00", tax: "13.00")
        transaction.amount_cents.should == 1200
        transaction.valid?.should be_true
      end

      it "defaults to Money::Currency format when no I18n information is present" do
        I18n.locale = "zxsw"
        Money.default_currency = Money::Currency.find('EUR')
        "12,00".to_money.should == Money.new(1200, :eur)
        transaction = Transaction.new(amount: "12,00", tax: "13,00")
        transaction.amount_cents.should == 1200
        transaction.valid?.should be_true
      end

      it "doesn't allow nil by default" do
        model.price_cents = nil
        model.should_not be_valid
      end

      context "with :allow_nil => true" do
        let(:validation_class) do
          Class.new(model_class) do
            monetize :price_cents, :allow_nil => true
          end
        end

        before(:each) { model.price = nil }

        it { should be_valid }
        specify { model.price.should be_nil }

        it "in blank assignments sets field to nil" do
          model.price = ""
          model.price.should be_nil
        end

      end

      it "doesn't raise exception if validation is used and nil is not allowed" do
        expect { model.price = nil }.to_not raise_error
      end

      it "doesn't save nil values if validation is used and nil is not allowed" do
        model.price = "1"
        model.price = nil
        model.price_cents.should_not be_nil
      end

      it "resets money_before_type_cast attr every time a save operation occurs" do
        v = Money.new(100, :usd)
        model.price = v
        model.price_money_before_type_cast.should == v
        model.valid?
        model.price_money_before_type_cast.should be_nil
        model.price = 10
        model.price_money_before_type_cast.should == 10
        model.valid?
        model.price_money_before_type_cast.should be_nil
      end

      it "uses Money default currency if no other currency is specified" do
        model.price = 1
        model.price.currency.should == Money.default_currency
      end

      context "with a registered currency on the model" do
        let(:validation_class) do
          Class.new(model_class) do
            register_currency :usd # Use USD as model level currency
            monetize :price_cents
          end
        end

        before(:each) { model.price = "1" }
        specify { model.price.currency.should == Money::Currency.find(:usd) }
        specify { validation_class.currency.should == Money::Currency.find(:usd) }
      end

      context "using a :with_currency argument" do
        let(:validation_class) do
          Class.new(model_class) do
            monetize :price_cents, :with_currency => :gbp
          end
        end

        before(:each) { model.price = 1 }
        specify { model.price.currency.should == Money::Currency.find(:gbp) }
      end

      it "correctly converts Fixnum objects into Money" do
        model.price = 25
        model.price.should == Money.new(2500, Money.default_currency)
      end

      it "correctly converts String objects into Money" do
        model.price = "25"
        model.price.should == Money.new(2500, Money.default_currency)
      end


      context "a model with an instance currency field" do
        let(:validation_class) do
          Class.new(model_class) do
            def currency; 'USD'; end
            monetize :price_cents, :with_currency => :gbp
          end
        end

        before(:each) { model.price = 1 }

        it "overrides a column with_currency" do
          model.price.currency_as_string.should == "USD"
        end
      end

      context "using with_model_currency" do
        let(:validation_class) do
          Class.new(model_class) do
            attr_accessor :currency_code
            monetize :price_cents, :with_model_currency => :currency_code
          end
        end

        before(:each) { model.price = 1 }

        it "has default currency if not specified" do
          model.price.currency_as_string.should == Money.default_currency.to_s
        end

        it "is overridden by instance currency column" do
          model.currency_code = 'CAD'
          model.price.currency_as_string.should == 'CAD'
        end
      end

      context "for model with currency column:", :integration => true do
        before :each do
          @transaction = Transaction.create(:amount_cents => 2400, :tax_cents => 600,
                                            :currency => :usd)
          @dummy_product1 = DummyProduct.create(:price_cents => 2400, :currency => :usd)
          @dummy_product2 = DummyProduct.create(:price_cents => 2600) # nil currency
        end

        it "serializes correctly the currency to a new instance of model" do
          d = DummyProduct.new
          d.price = Money.new(10, "EUR")
          d.save!
          d.reload
          d.currency.should == "EUR"
        end

        it "overrides default currency with the value of row currency" do
          @transaction.amount.currency.should == Money::Currency.find(:usd)
        end

        it "overrides default currency with the currency registered for the model" do
          @dummy_product2.price.currency.should == Money::Currency.find(:gbp)
        end

        it "overrides default and model currency with the row currency" do
          @dummy_product1.price.currency.should == Money::Currency.find(:usd)
        end

        it "constructs the money attribute from the stored mapped attribute values" do
          @transaction.amount.should == Money.new(2400, :usd)
        end

        it "instantiates correctly Money objects from the mapped attributes" do
          t = Transaction.new(:amount_cents => 2500, :currency => "CAD")
          t.amount.should == Money.new(2500, "CAD")
        end

        it "assigns correctly Money objects to the attribute" do
          @transaction.amount = Money.new(2500, :eur)
          @transaction.save.should be_true
          @transaction.amount.cents.should == Money.new(2500, :eur).cents
          @transaction.amount.currency_as_string.should == "EUR"
        end

        it "uses default currency if a non Money object is assigned to the attribute" do
          @transaction.amount = 234
          @transaction.amount.currency_as_string.should == "USD"
        end

        it "constructs the money object from the mapped method value" do
          @transaction.total.should == Money.new(3000, :usd)
        end
      end

      # Are these necessary? Does not correspond to any specific code in money-rails
      # that is not covered elsewhere

      #before :each do
      #  @product = Product.create(:price_cents => 3000, :discount => 150,
      #                            :bonus_cents => 200, :optional_price => 100,
      #                            :sale_price_amount => 1200)
      #  @service = Service.create(:charge_cents => 2000, :discount_cents => 120)
      #end
      #
      #it "assigns the correct value from a Money object using create" do
      #  @product = Product.create(:price => Money.new(3210, "USD"), :discount => 150,
      #                            :bonus_cents => 200, :optional_price => 100)
      #  @product.valid?.should be_true
      #  @product.price_cents.should == 3210
      #end
      #
      #it "updates correctly from a Money object using update_attributes" do
      #  @product.update_attributes(:price => Money.new(215, "USD")).should be_true
      #  @product.price_cents.should == 215
      #end

      #it "respects numericality validation when using update_attributes on money attribute" do
      #  @product.update_attributes(:price => "some text").should be_false
      #  @product.update_attributes(:price => Money.new(320, 'USD')).should be_true
      #end

      #it "respects numericality validation when using update_attributes" do
      #  @product.update_attributes(:price_cents => "some text").should be_false
      #  @product.update_attributes(:price_cents => 2000).should be_true
      #end


      # This probably should not have passed

      #it "assigns correctly Money objects to the attribute" do
      #  model.price = Money.new(2500, :USD)
      #  model.price.cents.should == 2500
      #  model.price.currency_as_string.should == "USD" # this only passed because Product's register_currency is USD
      #end
    end
  end
end
