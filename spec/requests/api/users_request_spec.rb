require 'rails_helper'

RSpec.describe Api::UsersController, type: :request do

  describe 'POST #create' do
    context 'with valid attributes' do
      before do
        Timecop.freeze Date.new(2017)
        payload = { email: 'john@doe.com' }
        post '/api/users', params: { user: payload }
      end

      after do
        Timecop.return
      end

      it 'succeeds' do
        expect(response).to have_http_status(:created)
      end

      it 'matches the users/create schema' do
        expect(response).to match_response_schema('users/create')
      end

      it 'saves the new user' do
        expect(User.find_by(email: 'john@doe.com')).to be_present
      end

      it 'returns the new user' do
        contact = JSON.parse(response.body)['user']
        expect(contact['id']).not_to be_nil
        expect(contact['email']).to eq('john@doe.com')
      end

      it 'returns a token valid for 1 day' do
        token = JSON.parse(response.body)['token']
        decoded_token = JsonWebToken.decode(token)
        expect(decoded_token[:exp]).to eq(1.day.from_now.to_i)
      end
    end

    context 'with missing paramenters' do
      before do
        post '/api/users', params: { }
      end

      it 'fails' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/parameter_missing')
      end

      it 'returns an error message' do
        body = JSON.parse(response.body)
        expect(body['message']).to eq('user param is missing or empty')
        expect(body['code']).to eq('missing_param')
        expect(body['resource']).to eq('user')
      end
    end

    context 'with existing email' do
      let(:email) { 'john@doe.com' }

      before do
        create :user, email: email
        payload = { email: email }
        post '/api/users', params: { user: payload }
      end

      it 'fails' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/record_invalid')
      end

      it 'returns errors' do
        body = JSON.parse(response.body)
        expect(body['message']).to eq('User validation failed')
        expect(body['code']).to eq('validation_failed')
        expect(body['resource']).to eq('User')
        expect(body['errors']).to eq({ 'email' => ['taken'] })
      end
    end
  end

  describe 'PATCH #activate' do
    let(:user) { create :user, email: 'john@doe.com' }

    context 'with valid attributes' do
      before do
        Timecop.freeze Date.new(2017)
        payload = {
          username: 'john',
          password: 'secret',
        }
        post "/api/users/#{ user.activation_token }/activate", params: { user: payload }
      end

      after do
        Timecop.return
      end

      it 'succeeds' do
        expect(response).to have_http_status(:ok)
      end

      it 'matches the users/activate schema' do
        expect(response).to match_response_schema('users/activate')
      end

      it 'activates the user' do
        expect(user.reload.activation_state).to eq('active')
      end

      it 'returns the new user' do
        contact = JSON.parse(response.body)['user']
        expect(contact['id']).not_to be_nil
        expect(contact['username']).to eq('john')
        expect(contact['email']).to eq('john@doe.com')
      end

      it 'returns a token valid for 1 month' do
        token = JSON.parse(response.body)['token']
        decoded_token = JsonWebToken.decode(token)
        expect(decoded_token[:exp]).to eq(1.month.from_now.to_i)
      end
    end

    context 'with missing attributes' do
      before do
        payload = {
          password: 'secret',
        }
        post "/api/users/#{ user.activation_token }/activate", params: { user: payload }
      end

      it 'fails' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/parameter_missing')
      end

      it 'returns an error message' do
        body = JSON.parse(response.body)
        expect(body['message']).to eq('username param is missing or empty')
        expect(body['code']).to eq('missing_param')
        expect(body['resource']).to eq('username')
      end
    end

    context 'with invalid username' do
      before do
        payload = {
          username: 'John Doe',
          password: 'secret',
        }
        post "/api/users/#{ user.activation_token }/activate", params: { user: payload }
      end

      it 'fails' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/record_invalid')
      end

      it 'returns errors' do
        body = JSON.parse(response.body)
        expect(body['message']).to eq('User validation failed')
        expect(body['code']).to eq('validation_failed')
        expect(body['resource']).to eq('User')
        expect(body['errors']).to eq({ 'username' => ['invalid'] })
      end
    end

    context 'with existing username' do
      before do
        create :user, username: 'john'
        payload = {
          username: 'john',
          password: 'secret',
        }
        post "/api/users/#{ user.activation_token }/activate", params: { user: payload }
      end

      it 'fails' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/record_invalid')
      end

      it 'returns errors' do
        body = JSON.parse(response.body)
        expect(body['message']).to eq('User validation failed')
        expect(body['code']).to eq('validation_failed')
        expect(body['resource']).to eq('User')
        expect(body['errors']).to eq({ 'username' => ['taken'] })
      end
    end

    context 'with invalid token' do
      before do
        payload = { password: 'secret' }
        post "/api/users/not_the_token/activate", params: { user: payload }
      end

      it 'fails' do
        expect(response).to have_http_status(:not_found)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/record_not_found')
      end

      it 'returns an error message' do
        body = JSON.parse(response.body)
        expect(body['message']).to eq('User not found')
        expect(body['code']).to eq('not_found')
        expect(body['resource']).to eq('User')
      end
    end
  end

  describe 'POST #authorize' do
    context 'with valid username and password' do
      let(:payload) { { username: 'john', password: 'secret' } }

      before do
        Timecop.freeze Date.new(2017)
        create :user, :activated, username: 'john', password: 'secret'
        post '/api/users/authorize', params: payload
      end

      after do
        Timecop.return
      end

      it 'succeeds' do
        expect(response).to have_http_status(:ok)
      end

      it 'matches the users/authorize format' do
        expect(response).to match_response_schema('users/authorize')
      end

      it 'returns a token valid for 1 month' do
        token = JSON.parse(response.body)['token']
        decoded_token = JsonWebToken.decode(token)
        expect(decoded_token[:exp]).to eq(1.month.from_now.to_i)
      end
    end

    context 'with inactive user' do
      let(:payload) { { username: 'john', password: 'secret' } }

      before do
        create :user, username: 'john', password: 'secret'
        post '/api/users/authorize', params: payload
      end

      it 'fails' do
        expect(response).to have_http_status(:unauthorized)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/custom_error')
      end

      it 'returns an error message' do
        error = JSON.parse(response.body)
        expect(error['message']).to eq('Bad credentials')
        expect(error['code']).to eq('login_failed')
      end
    end

    context 'with invalid password' do
      let(:payload) { { username: 'john', password: 'wrong secret' } }

      before do
        create :user, :activated, username: 'john', password: 'secret'
        post '/api/users/authorize', params: payload
      end

      it 'fails' do
        expect(response).to have_http_status(:unauthorized)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/custom_error')
      end

      it 'returns an error message' do
        error = JSON.parse(response.body)
        expect(error['message']).to eq('Bad credentials')
        expect(error['code']).to eq('login_failed')
      end
    end
  end

  describe 'GET #me' do
    let(:user) { create :user }

    context 'with valid token' do
      before do
        Timecop.freeze DateTime.new(2017)
        create :project, :finished, user: user, name: 'my-finished-project'
        create :project, :in_progress, user: user,
                                       name: 'my-project',
                                       started_at: 15.days.ago,
                                       due_at: 15.days.from_now
        get '/api/users/me', headers: { 'Authorization': user.token }
      end

      after do
        Timecop.return
      end

      it 'succeeds' do
        expect(response).to have_http_status(:ok)
      end

      it 'matches the users/user schema' do
        expect(response).to match_response_schema('users/me')
      end

      it 'returns the corresponding user' do
        json_user = JSON.parse(response.body)['user']
        expect(json_user['id']).to eq(user.id)
      end

      it 'does not include finished project' do
        projects = JSON.parse(response.body)['projects']
        expect(projects.length).to eq(1)
        expect(projects[0]['name']).not_to eq('my-finished-project')
      end

      it 'returns number of finished projects' do
        expect(JSON.parse(response.body)['numberFinishedProjects']).to eq(1)
      end

      it 'includes in progress project' do
        projects = JSON.parse(response.body)['projects']
        expect(projects.length).to eq(1)
        expect(projects[0]['name']).to eq('my-project')
        expect(projects[0]['userId']).to eq(user.id)
        expect(projects[0]['startedAt']).to eq(15.days.ago.to_i)
        expect(projects[0]['dueAt']).to eq(15.days.from_now.to_i)
      end
    end

    context 'with token of a deleted user' do
      before do
        user.destroy
        get '/api/users/me', headers: { 'Authorization': user.token }
      end

      it 'fails' do
        expect(response).to have_http_status(:not_found)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/record_not_found')
      end

      it 'returns an error message' do
        body = JSON.parse(response.body)
        expect(body['message']).to eq('User not found')
        expect(body['code']).to eq('not_found')
        expect(body['resource']).to eq('User')
      end
    end

    context 'with expired token' do
      before do
        get '/api/users/me', headers: { 'Authorization': user.token(1.day.ago) }
      end

      it 'fails' do
        expect(response).to have_http_status(:unauthorized)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/custom_error')
      end

      it 'returns an error message' do
        error = JSON.parse(response.body)
        expect(error['message']).to eq('Authentication is required')
        expect(error['code']).to eq('authentication_required')
      end
    end

    context 'with no Authorization header' do
      before do
        get '/api/users/me'
      end

      it 'fails' do
        expect(response).to have_http_status(:unauthorized)
      end

      it 'matches the error schema' do
        expect(response).to match_response_schema('errors/custom_error')
      end

      it 'returns an error message' do
        error = JSON.parse(response.body)
        expect(error['message']).to eq('Authentication is required')
        expect(error['code']).to eq('authentication_required')
      end
    end
  end

end
