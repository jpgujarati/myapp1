FROM node:8
WORKDIR /user/src/app
COPY package*.json ./
RUN npm install
COPY . . 
CMD [ "npm", "start"] 
EXPOSE 8081
