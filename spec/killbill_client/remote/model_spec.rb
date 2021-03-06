require 'spec_helper'

describe KillBillClient::Model do
  it 'should manipulate accounts', :integration => true  do
    # In case the remote server has lots of data
    search_limit = 100000

    external_key = Time.now.to_i.to_s

    account = KillBillClient::Model::Account.new
    account.name = 'KillBillClient'
    account.external_key = external_key
    account.email = 'kill@bill.com'
    account.currency = 'USD'
    account.time_zone = 'UTC'
    account.address1 = '5, ruby road'
    account.address2 = 'Apt 4'
    account.postal_code = 10293
    account.company = 'KillBill, Inc.'
    account.city = 'SnakeCase'
    account.state = 'Awesome'
    account.country = 'LalaLand'
    account.locale = 'FR_fr'
    account.is_notified_for_invoices = false
    account.account_id.should be_nil

    # Create and verify the account
    account = account.create('KillBill Spec test')
    account.external_key.should == external_key
    account.account_id.should_not be_nil
    account_id = account.account_id

    # Try to retrieve it
    account = KillBillClient::Model::Account.find_by_id account.account_id
    account.external_key.should == external_key
    account.payment_method_id.should be_nil

    # Try to retrieve it
    account = KillBillClient::Model::Account.find_by_external_key external_key
    account.account_id.should == account_id
    account.payment_method_id.should be_nil

    # Try to retrieve it (bis repetita placent)
    accounts = KillBillClient::Model::Account.find_in_batches(0, search_limit)
    # Can't test equality if the remote server has extra data
    accounts.pagination_total_nb_records.should >= 1
    accounts.pagination_max_nb_records.should >= 1
    accounts.size.should >= 1
    # If the remote server has lots of data, we need to page through the results (good test!)
    found = nil
    accounts.each_in_batches do |account|
      found = account if account.external_key == external_key
      break unless found.nil?
    end
    found.should_not be_nil

    # Try to retrieve it via the search API
    accounts = KillBillClient::Model::Account.find_in_batches_by_search_key(account.name, 0, search_limit)
    # Can't test equality if the remote server has extra data
    accounts.pagination_total_nb_records.should >= 1
    accounts.pagination_max_nb_records.should >= 1
    accounts.size.should >= 1
    # If the remote server has lots of data, we need to page through the results (good test!)
    found = nil
    accounts.each_in_batches do |account|
      found = account if account.external_key == external_key
      break unless found.nil?
    end
    found.should_not be_nil

    # Add/Remove a tag
    account.tags.size.should == 0
    account.add_tag('TEST', 'KillBill Spec test')
    tags = account.tags
    tags.size.should == 1
    tags.first.tag_definition_name.should == 'TEST'
    account.remove_tag('TEST', 'KillBill Spec test')
    account.tags.size.should == 0

    # Add/Remove a custom field
    account.custom_fields.size.should == 0
    custom_field = KillBillClient::Model::CustomField.new
    custom_field.name = Time.now.to_i.to_s
    custom_field.value = Time.now.to_i.to_s
    account.add_custom_field(custom_field, 'KillBill Spec test')
    custom_fields = account.custom_fields
    custom_fields.size.should == 1
    custom_fields.first.name.should == custom_field.name
    custom_fields.first.value.should == custom_field.value
    account.remove_custom_field(custom_fields.first.custom_field_id, 'KillBill Spec test')
    account.custom_fields.size.should == 0

    # Add a payment method
    pm = KillBillClient::Model::PaymentMethod.new
    pm.account_id = account.account_id
    pm.is_default = true
    pm.plugin_name = '__EXTERNAL_PAYMENT__'
    pm.plugin_info = {}
    pm.payment_method_id.should be_nil

    pm = pm.create(true, 'KillBill Spec test')
    pm.payment_method_id.should_not be_nil

    # Try to retrieve it
    pm = KillBillClient::Model::PaymentMethod.find_by_id pm.payment_method_id, true
    pm.account_id.should == account.account_id

    # Try to retrieve it (bis repetita placent)
    pms = KillBillClient::Model::PaymentMethod.find_in_batches(0, search_limit)
    # Can't test equality if the remote server has extra data
    pms.pagination_total_nb_records.should >= 1
    pms.pagination_max_nb_records.should >= 1
    pms.size.should >= 1
    # If the remote server has lots of data, we need to page through the results (good test!)
    found = nil
    pms.each_in_batches do |payment_method|
      found = payment_method if payment_method.payment_method_id == pm.payment_method_id
      break unless found.nil?
    end
    found.should_not be_nil

    account = KillBillClient::Model::Account.find_by_id account.account_id
    account.payment_method_id.should == pm.payment_method_id

    pms = KillBillClient::Model::PaymentMethod.find_all_by_account_id account.account_id
    pms.size.should == 1
    pms[0].payment_method_id.should == pm.payment_method_id

    # Check there is no payment associated with that account
    account.payments.size.should == 0

    # Add an external charge
    invoice_item = KillBillClient::Model::InvoiceItem.new
    invoice_item.account_id = account.account_id
    invoice_item.currency = account.currency
    invoice_item.amount = 123.98

    invoice_item = invoice_item.create 'KillBill Spec test'
    invoice = KillBillClient::Model::Invoice.find_by_id_or_number invoice_item.invoice_id

    invoice.balance.should == 123.98

    # Check the account balance
    account = KillBillClient::Model::Account.find_by_id account.account_id, true
    account.account_balance.should == 123.98

    pm.destroy(true, 'KillBill Spec test')

    account = KillBillClient::Model::Account.find_by_id account.account_id
    account.payment_method_id.should be_nil

    # Get its timeline
    timeline = KillBillClient::Model::AccountTimeline.find_by_account_id account.account_id

    timeline.account.external_key.should == external_key
    timeline.account.account_id.should_not be_nil

    timeline.invoices.should be_a_kind_of Array
    timeline.invoices.should_not be_empty
    timeline.payments.should be_a_kind_of Array
    timeline.bundles.should be_a_kind_of Array

    # Let's find the invoice by two methods
    invoice = timeline.invoices.first
    invoice_id = invoice.invoice_id
    invoice_number = invoice.invoice_number

    invoice_with_id = KillBillClient::Model::Invoice.find_by_id_or_number invoice_id
    invoice_with_number = KillBillClient::Model::Invoice.find_by_id_or_number invoice_number

    invoice_with_id.invoice_id.should == invoice_with_number.invoice_id
    invoice_with_id.invoice_number.should == invoice_with_number.invoice_number

    # Create an external payment for each unpaid invoice
    invoice_payment = KillBillClient::Model::InvoicePayment.new
    invoice_payment.account_id = account.account_id
    invoice_payment.bulk_create true, 'KillBill Spec test'

    # Try to retrieve it
    payments = KillBillClient::Model::Payment.find_in_batches(0, search_limit)
    # Can't test equality if the remote server has extra data
    payments.pagination_total_nb_records.should >= 1
    payments.pagination_max_nb_records.should >= 1
    payments.size.should >= 1
    # If the remote server has lots of data, we need to page through the results (good test!)
    found = nil
    payments.each_in_batches do |p|
      found = p if p.account_id == account.account_id
      break unless found.nil?
    end
    found.should_not be_nil

    # Try to retrieve it (bis repetita placent)
    invoice_payment = KillBillClient::Model::InvoicePayment.find_by_id found.payment_id
    invoice_payment.account_id.should == account.account_id

    # Try to retrieve it
    invoice = KillBillClient::Model::Invoice.new
    invoice.invoice_id = invoice_payment.target_invoice_id
    payments = invoice.payments
    payments.size.should == 1
    payments.first.account_id.should == account.account_id

    # Check the account balance
    account = KillBillClient::Model::Account.find_by_id account.account_id, true
    account.account_balance.should == 0

    # Verify the timeline
    timeline = KillBillClient::Model::AccountTimeline.find_by_account_id account.account_id
    timeline.payments.should_not be_empty
    invoice_payment = timeline.payments.first
    timeline.payments.first.transactions.size.should == 1
    timeline.payments.first.transactions.first.transaction_type.should == 'PURCHASE'
    invoice_payment.auth_amount.should == 0
    invoice_payment.captured_amount.should == 0
    invoice_payment.purchased_amount.should == invoice_payment.purchased_amount
    invoice_payment.refunded_amount.should == 0
    invoice_payment.credited_amount.should == 0

    # Refund the payment (with item adjustment)
    invoice_item = KillBillClient::Model::Invoice.find_by_id_or_number(invoice_number, true).items.first
    item = KillBillClient::Model::InvoiceItem.new
    item.invoice_item_id = invoice_item.invoice_item_id
    item.amount = invoice_item.amount
    refund = KillBillClient::Model::InvoicePayment.refund invoice_payment.payment_id, invoice_payment.purchased_amount, [item], 'KillBill Spec test'

    # Verify the refund
    timeline = KillBillClient::Model::AccountTimeline.find_by_account_id account.account_id
    timeline.payments.should_not be_empty
    timeline.payments.size.should == 1
    timeline.payments.first.transactions.size.should == 2
    timeline.payments.first.transactions.first.transaction_type.should == 'PURCHASE'
    refund = timeline.payments.first.transactions.last
    refund.transaction_type.should == 'REFUND'
    refund.amount.should == invoice_item.amount

    # Create a credit for invoice
    new_credit = KillBillClient::Model::Credit.new
    new_credit.credit_amount = 10.1
    new_credit.invoice_id = invoice_id
    new_credit.effective_date = "2013-09-30"
    new_credit.account_id = account.account_id
    new_credit.create 'KillBill Spec test'

    # Verify the invoice item of the credit
    invoice = KillBillClient::Model::Invoice.find_by_id_or_number invoice_id
    invoice.items.should_not be_empty
    item = invoice.items.last
    item.invoice_id.should == invoice_id
    item.amount.should == 10.1
    item.account_id.should == account.account_id

    # Verify the credit
    account = KillBillClient::Model::Account.find_by_id account.account_id, true
    account.account_balance.should == -10.1

    # Create a subscription
    sub = KillBillClient::Model::Subscription.new
    sub.account_id = account.account_id
    sub.external_key = Time.now.to_i.to_s
    sub.product_name = 'Sports'
    sub.product_category = 'BASE'
    sub.billing_period = 'MONTHLY'
    sub.price_list = 'DEFAULT'
    sub = sub.create 'KillBill Spec test'

    # Verify we can retrieve it
    account.bundles.size.should == 1
    account.bundles[0].subscriptions.size.should == 1
    account.bundles[0].subscriptions[0].subscription_id.should == sub.subscription_id
    bundle = account.bundles[0]

    # Verify we can retrieve it by id
    KillBillClient::Model::Bundle.find_by_id(bundle.bundle_id).should == bundle

    # Verify we can retrieve it by external key
    KillBillClient::Model::Bundle.find_by_external_key(bundle.external_key).should == bundle

    # Verify we can retrieve it by account id and external key
    bundles = KillBillClient::Model::Bundle.find_all_by_account_id_and_external_key(account.account_id, bundle.external_key)
    bundles.size.should == 1
    bundles[0].should == bundle
  end

  it 'should manipulate tag definitions' do
    KillBillClient::Model::TagDefinition.all.size.should > 0
    KillBillClient::Model::TagDefinition.find_by_name('TEST').is_control_tag.should be_true

    tag_definition_name = Time.now.to_i.to_s
    KillBillClient::Model::TagDefinition.find_by_name(tag_definition_name).should be_nil

    tag_definition = KillBillClient::Model::TagDefinition.new
    tag_definition.name = tag_definition_name
    tag_definition.description = 'Tag for unit test'
    tag_definition.create('KillBill Spec test').id.should_not be_nil

    found_tag_definition = KillBillClient::Model::TagDefinition.find_by_name(tag_definition_name)
    found_tag_definition.name.should == tag_definition_name
    found_tag_definition.description.should == tag_definition.description
    found_tag_definition.is_control_tag.should be_false
  end

  it 'should manipulate tenants', :integration => true  do
    api_key = Time.now.to_i.to_s + Random.rand(100).to_s
    api_secret = 'S4cr3333333t!!!!!!lolz'

    tenant = KillBillClient::Model::Tenant.new
    tenant.api_key = api_key
    tenant.api_secret = api_secret

    # Create and verify the tenant
    tenant = tenant.create('KillBill Spec test')
    tenant.api_key.should == api_key
    tenant.tenant_id.should_not be_nil

    # Try to retrieve it by id
    tenant = KillBillClient::Model::Tenant.find_by_id tenant.tenant_id
    tenant.api_key.should == api_key

    # Try to retrieve it by api key
    tenant = KillBillClient::Model::Tenant.find_by_api_key tenant.api_key
    tenant.api_key.should == api_key
  end

  it 'should manipulate the catalog', :integration => true do
    plans = KillBillClient::Model::Catalog::available_base_plans
    plans.size.should > 0
    plans[0].plan.should_not be_nil
  end

  #it 'should retrieve users permissions' do
  #  # Tough to verify as it depends on the Kill Bill configuration
  #  puts KillBillClient::Model::Security.find_permissions
  #  puts KillBillClient::Model::Security.find_permissions(:username => 'admin', :password => 'password')
  #end
end
