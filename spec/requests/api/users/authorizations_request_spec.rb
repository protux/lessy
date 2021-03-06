require 'rails_helper'
require 'shared_examples_for_failures'

RSpec.describe Api::Users::AuthorizationsController, type: :request do

  before do
    Timecop.freeze Date.new(2017)
  end

  after do
    Timecop.return
  end

  describe 'POST #create' do
    let!(:user) { create :user, :inactive, username: 'john', password: 'secret' }
    let(:payload) { {
      username: 'john',
      password: 'secret',
    } }

    subject { post api_users_authorizations_path, params: payload,
                                                  as: :json }

    context 'with valid username and password' do
      before do
        user.activate!
        subject
      end

      it 'succeeds' do
        expect(response).to have_http_status(:ok)
      end

      it 'matches the users/authorizations/create format' do
        expect(response).to match_response_schema('users/authorizations/create')
      end

      it 'returns a token valid for 1 month' do
        token = JSON.parse(response.body)['meta']['token']
        decoded_token = JsonWebToken.decode(token)
        expect(decoded_token[:exp]).to eq(1.month.from_now.to_i)
      end
    end

    context 'with inactive user' do
      before { subject }

      it_behaves_like 'API errors', :unauthorized, {
        errors: [{
          status: '401 Unauthorized',
          code: 'login_failed',
          title: 'Credentials are wrong',
          detail: 'You failed to authenticate yourself, credentials are probably wrong.',
        }],
      }
    end

    context 'with invalid password' do
      let(:payload) { {
        username: 'john',
        password: 'wrong secret',
      } }

      before do
        user.activate!
        subject
      end

      it_behaves_like 'API errors', :unauthorized, {
        errors: [{
          status: '401 Unauthorized',
          code: 'login_failed',
          title: 'Credentials are wrong',
          detail: 'You failed to authenticate yourself, credentials are probably wrong.',
        }],
      }
    end
  end

end
